#!/bin/bash
# Deploy add-on changes that Hermes merged and verified (task DONE, post-merge verification PASSED).
#
# For each add-on in custom-addons/ that Hermes manages (its clone in $HERMES_PROJECTS/odoo-base/custom-addons/),
# the newest verified merge commit is fast-forwarded into this copy, then the README procedure runs:
# backup, build, `-u` of the changed add-ons, start. Run by the odoo-autodeploy systemd user timer.
#
# Never overwrites local work: an add-on with uncommitted changes, or one that cannot fast-forward, is skipped.
# If the update fails, the previous image and add-on commits are restored and Odoo starts again on them.
set -euo pipefail
cd "$(dirname "$0")/.."

HERMES_DIR=${HERMES_DIR:-/home/gp/hermes-orchestrator}
HERMES_PROJECTS=${HERMES_PROJECTS:-/srv/HermesProjects}
STATE_DIR=${STATE_DIR:-$HOME/.local/state/odoo-autodeploy}
mkdir -p "$STATE_DIR"
exec 9>"$STATE_DIR/lock"
flock -n 9 || exit 0  # a deploy is already running

log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*"; }
ho() { docker compose --project-directory "$HERMES_DIR" exec -T control-plane ho "$@"; }

# Verified merge commits of a project, one per line. DONE is terminal, so each task's answer is cached.
verified_commits() {
    local slug=$1 cache="$STATE_DIR/verified-$1" key sha
    touch "$cache"
    for key in $(ho task list --project "$slug" --state DONE | python3 -c \
            'import json,sys; print("\n".join(t["key"] for t in json.load(sys.stdin)["tasks"]))'); do
        if ! grep -q "^$key " "$cache"; then
            sha=$(ho git status "$key" | python3 -c 'import json,sys
c = json.load(sys.stdin).get("changes") or {}
print(c["merge_commit_sha"] if c.get("merge_commit_sha") and c.get("post_merge_status") == "PASSED" else "-")')
            echo "$key $sha" >>"$cache"
        fi
    done
    awk '$2 != "-" {print $2}' "$cache"
}

projects=$(ho project list | python3 -c 'import json,sys
for p in json.load(sys.stdin)["projects"]:
    print(p["slug"], p["host_path"])')

changed=() previous=()
for dir in custom-addons/*/; do
    addon=$(basename "$dir")
    slug=$(awk -v p="$HERMES_PROJECTS/odoo-base/custom-addons/$addon" '$2 == p {print $1}' <<<"$projects")
    [ -n "$slug" ] || continue
    source="$HERMES_PROJECTS/odoo-base/custom-addons/$addon"
    head=$(git -C "$dir" rev-parse HEAD)
    target=""
    for sha in $(verified_commits "$slug"); do
        git -C "$source" cat-file -e "$sha^{commit}" 2>/dev/null || continue
        if [ -z "$target" ] || git -C "$source" merge-base --is-ancestor "$target" "$sha"; then target=$sha; fi
    done
    [ -n "$target" ] || continue
    git -C "$dir" cat-file -e "$target^{commit}" 2>/dev/null || git -C "$dir" fetch -q "$source" "$target"
    git -C "$dir" merge-base --is-ancestor "$target" "$head" && continue  # already deployed
    if [ -n "$(git -C "$dir" status --porcelain)" ]; then
        log "skip $addon: uncommitted changes in $dir"; continue
    fi
    if ! git -C "$dir" merge-base --is-ancestor "$head" "$target"; then
        log "skip $addon: $dir has commits that are not in ${target:0:12}"; continue
    fi
    changed+=("$addon") previous+=("$head")
    git -C "$dir" merge -q --ff-only "$target"
    log "$addon: ${head:0:12} -> ${target:0:12}"
done
[ ${#changed[@]} -gt 0 ] || exit 0

modules=$(IFS=,; echo "${changed[*]}")
image=$(docker compose config --format json | python3 -c 'import json,sys
d = json.load(sys.stdin); print(d["services"]["odoo"].get("image") or d["name"] + "-odoo")')
old_image=$(docker image inspect -f '{{.Id}}' "$image" 2>/dev/null || true)

rollback() {
    log "deploy of $modules failed: restoring the previous add-ons and image"
    local i
    for i in "${!changed[@]}"; do git -C "custom-addons/${changed[$i]}" reset -q --hard "${previous[$i]}"; done
    [ -n "$old_image" ] && docker image tag "$old_image" "$image"
    docker compose up -d --no-build odoo
    exit 1
}

log "deploying $modules"
sh scripts/backup.sh
docker compose build odoo || rollback
docker compose stop odoo
docker compose run --rm odoo -u "$modules" --stop-after-init --no-http --workers=0 --max-cron-threads=0 || rollback
docker compose up -d --no-build odoo
for _ in $(seq 60); do
    status=$(docker inspect -f '{{.State.Health.Status}}' "$(docker compose ps -q odoo)" 2>/dev/null || true)
    if [ "$status" = healthy ]; then log "deployed $modules"; exit 0; fi
    sleep 5
done
log "deployed $modules, but Odoo is not healthy yet ($status): check docker compose logs odoo"
exit 1
