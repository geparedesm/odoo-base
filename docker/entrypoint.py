"""Keep secrets out of arguments and refuse to serve an unsecured new database."""
import configparser
import os
from pathlib import Path
import subprocess
import sys
import time

import psycopg2


def secret(name):
    value = Path('/run/secrets', name).read_text().strip()
    if len(value) < 24 or '\n' in value:
        raise RuntimeError(f'{name}: se requiere un secreto de al menos 24 caracteres')
    return value


def main():
    os.umask(0o077)
    config = configparser.ConfigParser(interpolation=None)
    config.read('/etc/odoo/odoo.conf')
    options = config['options']
    options['db_password'] = secret('odoo_db_password')
    options['admin_passwd'] = secret('odoo_master_password')
    for key, env in [('workers', 'APP_WORKERS'),
                     ('limit_memory_soft', 'APP_MEMORY_SOFT'),
                     ('limit_memory_hard', 'APP_MEMORY_HARD')]:
        options[key] = str(int(os.environ.get(env, options[key])))
    with open('/tmp/odoo-runtime.conf', 'w') as output:
        config.write(output)
    os.environ['ODOO_RC'] = '/tmp/odoo-runtime.conf'
    # Calling the Python script explicitly also applies our dependency venv.
    odoo = ['python3', '/usr/bin/odoo']
    mode, *args = sys.argv[1:] or ['serve']
    if mode == 'scaffold':
        os.execvp(odoo[0], odoo + [mode] + args)

    for attempt in range(60):
        try:
            connection = psycopg2.connect(host='db', dbname='odoo', user='odoo',
                                          password=options['db_password'], connect_timeout=3)
            break
        except psycopg2.OperationalError:
            if attempt == 59:
                raise
            time.sleep(2)
    with connection.cursor() as cursor:
        cursor.execute("SELECT to_regclass('public.ir_config_parameter')")
        exists = cursor.fetchone()[0] is not None
        ready = False
        if exists:
            cursor.execute("SELECT value FROM ir_config_parameter WHERE key = %s",
                           ('deployment.initialized',))
            ready = cursor.fetchone() == ('yes',)
    connection.close()

    if mode == 'bootstrap':
        if ready:
            print('Base ya inicializada; no se modifica la contraseña.')
            return
        if exists:
            raise RuntimeError('Base existente sin marca de inicialización. Revisa manualmente antes de continuar.')
        secret('odoo_admin_password')
        subprocess.run(odoo + ['-i', 'base', '--without-demo', '--stop-after-init',
                              '--no-http', '--workers=0', '--max-cron-threads=0'], check=True)
        subprocess.run(odoo + ['shell', '--no-http', '--workers=0', '--max-cron-threads=0'],
                       input="""from pathlib import Path
password = Path('/run/secrets/odoo_admin_password').read_text().strip()
env.ref('base.user_admin').write({'login': 'admin', 'password': password})
env['ir.config_parameter'].sudo().set_param('deployment.initialized', 'yes')
env.cr.commit()
""", text=True, check=True)
        return
    if not ready:
        raise RuntimeError('Ejecuta primero: docker compose run --rm odoo bootstrap')
    if mode == 'serve':
        os.execvp(odoo[0], odoo + args)
    if mode == 'shell' or mode.startswith('-'):
        os.execvp(odoo[0], odoo + [mode] + args)
    raise RuntimeError(f'Comando no admitido: {mode}')


if __name__ == '__main__':
    main()
