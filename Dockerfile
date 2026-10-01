ARG ODOO_IMAGE=odoo:19.0-20260926
FROM ${ODOO_IMAGE}
USER root
RUN apt-get update && apt-get install -y --no-install-recommends python3-venv \
    && rm -rf /var/lib/apt/lists/*
COPY requirements.txt /tmp/custom-requirements.txt
RUN python3 -m venv --system-site-packages /opt/odoo-venv \
    && /opt/odoo-venv/bin/pip install --no-cache-dir -r /tmp/custom-requirements.txt \
    && rm /tmp/custom-requirements.txt
ENV PATH="/opt/odoo-venv/bin:${PATH}"
COPY --chown=odoo:odoo config/odoo.conf /etc/odoo/odoo.conf
COPY --chown=odoo:odoo custom-addons/ /opt/custom-addons/
COPY docker/entrypoint.py /usr/local/bin/production-entrypoint.py
USER odoo
ENTRYPOINT ["python3", "/usr/local/bin/production-entrypoint.py"]
CMD ["serve"]
