"""Security checks for first start; no Docker or database needed."""
import configparser
import importlib.util
from pathlib import Path
import sys
import types
import unittest
from unittest.mock import MagicMock, mock_open, patch


spec = importlib.util.spec_from_file_location(
    'entrypoint', Path(__file__).resolve().parents[1] / 'docker/entrypoint.py')
entrypoint = importlib.util.module_from_spec(spec)
with patch.dict(sys.modules, {'psycopg2': types.SimpleNamespace()}):
    spec.loader.exec_module(entrypoint)


class StartupSecurityTests(unittest.TestCase):
    def run_mode(self, mode, exists=False, ready=False):
        config = configparser.ConfigParser(interpolation=None)
        config.read_dict({'options': {'workers': '2', 'limit_memory_soft': '536870912',
                                      'limit_memory_hard': '671088640'}})
        connection = MagicMock()
        cursor = connection.cursor.return_value.__enter__.return_value
        cursor.fetchone.side_effect = [('ir_config_parameter' if exists else None,),
                                       ('yes',) if ready else None]
        patches = [
            patch.object(entrypoint.configparser, 'ConfigParser', return_value=config),
            patch.object(config, 'read'),
            patch.object(entrypoint, 'secret', return_value='x' * 64),
            patch.object(entrypoint.psycopg2, 'connect', return_value=connection, create=True),
            patch.object(entrypoint.os, 'umask'),
            patch.dict(entrypoint.os.environ, {}, clear=True),
            patch.object(sys, 'argv', ['entrypoint.py', mode]),
            patch('builtins.open', mock_open()),
        ]
        from contextlib import ExitStack
        with ExitStack() as stack:
            for context in patches:
                stack.enter_context(context)
            entrypoint.main()

    @patch.object(entrypoint.os, 'execvp')
    def test_uninitialized_database_cannot_serve(self, execute):
        with self.assertRaisesRegex(RuntimeError, 'bootstrap'):
            self.run_mode('serve')
        execute.assert_not_called()

    @patch.object(entrypoint.subprocess, 'run')
    def test_existing_unsecured_database_requires_review(self, run):
        with self.assertRaisesRegex(RuntimeError, 'Revisa manualmente'):
            self.run_mode('bootstrap', exists=True)
        run.assert_not_called()

    @patch.object(entrypoint.subprocess, 'run')
    def test_repeated_bootstrap_does_not_reset_password(self, run):
        self.run_mode('bootstrap', exists=True, ready=True)
        run.assert_not_called()

    @patch.object(entrypoint.subprocess, 'run')
    def test_bootstrap_never_opens_http(self, run):
        self.run_mode('bootstrap')
        self.assertEqual(run.call_count, 2)
        for call in run.call_args_list:
            self.assertIn('--no-http', call.args[0])
            self.assertNotIn('x' * 64, ' '.join(call.args[0]))

    @patch.object(entrypoint.os, 'execvp', side_effect=SystemExit(0))
    def test_ready_database_starts_without_secrets_in_arguments(self, execute):
        with self.assertRaises(SystemExit):
            self.run_mode('serve', exists=True, ready=True)
        self.assertNotIn('x' * 64, str(execute.call_args))


if __name__ == '__main__':
    unittest.main()
