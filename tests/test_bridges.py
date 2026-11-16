import importlib.util
import os
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


opencode = load("opencode_bridge", os.path.join(ROOT, "scripts", "opencode_bridge.py"))
copilot = load("copilot_bridge", os.path.join(ROOT, "scripts", "copilot_bridge.py"))
recorder = load("recorder_bridge", os.path.join(ROOT, "scripts", "recorder_bridge.py"))


class TokenInfoTest(unittest.TestCase):
    def test_empty(self):
        self.assertEqual(opencode.token_info(None), None)

    def test_normalizes_cache(self):
        self.assertEqual(
            opencode.token_info({
                "input": 10, "output": 4, "reasoning": 2,
                "cache": {"read": 7, "write": 3},
            }),
            {"input": 10, "output": 4, "reasoning": 2, "cacheRead": 7, "cacheWrite": 3},
        )


class SessionTest(unittest.TestCase):
    def test_normalize_session(self):
        info = {
            "id": "ses_1",
            "title": "Projeto",
            "model": {"id": "deepseek", "providerID": "opencode-go", "variant": "max"},
            "cost": 1.25,
            "tokens": {"input": 3, "output": 2},
            "outcome": "succeeded",
            "location": {"directory": "/tmp"},
            "time": {"updated": 42, "busy": 30, "idle": 20},
        }
        result = opencode.normalize_session(info)
        self.assertEqual(result["session"], "ses_1")
        self.assertEqual(result["provider"], "opencode-go")
        self.assertEqual(result["directory"], "/tmp")
        self.assertTrue(result["running"])

    def test_normalize_session_running_false(self):
        info = {
            "id": "ses_1", "time": {"busy": 10, "idle": 20},
        }
        self.assertFalse(opencode.normalize_session(info)["running"])


class ModelRefTest(unittest.TestCase):
    def test_plain(self):
        self.assertEqual(
            opencode.model_ref("opencode-go/deepseek-v4.1-flash"),
            {"id": "deepseek-v4.1-flash", "providerID": "opencode-go"},
        )

    def test_variant(self):
        self.assertEqual(
            opencode.model_ref("opencode-go/deepseek-v4.1-flash#max"),
            {"id": "deepseek-v4.1-flash", "providerID": "opencode-go", "variant": "max"},
        )

    def test_invalid(self):
        self.assertIsNone(opencode.model_ref("deepseek"))
        self.assertIsNone(opencode.model_ref("/model"))


class ContentTest(unittest.TestCase):
    def test_text_parts(self):
        content = [
            {"type": "text", "text": "um"},
            {"type": "image", "data": "..."},
            {"type": "text", "text": "dois"},
        ]
        self.assertEqual(opencode.content_text(content), "um\ndois")
        self.assertEqual(copilot.content_text(content), "um\ndois")

    def test_empty(self):
        self.assertEqual(opencode.content_text(None), "")
        self.assertEqual(copilot.content_text([]), "")


class CopilotModelTest(unittest.TestCase):
    def test_prefers_included_model(self):
        models = {
            "currentModelId": "claude-haiku-4.5",
            "availableModels": [
                {"modelId": "claude-haiku-4.5", "_meta": {"copilotUsage": "0.33x"}},
                {"modelId": "gpt-4.1", "_meta": {"copilotUsage": "0x"}},
            ],
        }
        self.assertEqual(copilot.choose_model(models), "gpt-4.1")

    def test_falls_back_to_current(self):
        models = {
            "currentModelId": "gpt-4.1",
            "availableModels": [{"modelId": "gpt-4.1"}],
        }
        self.assertEqual(copilot.choose_model(models), "gpt-4.1")

    def test_empty(self):
        self.assertEqual(copilot.choose_model({}), "")


class PermissionsTest(unittest.TestCase):
    def test_browser_denied(self):
        self.assertTrue(opencode.browser_denied(opencode.SESSION_PERMISSIONS))
        self.assertTrue(opencode.browser_denied([
            {"action": "*", "resource": "*", "effect": "allow"},
            {"action": "browser", "resource": "*", "effect": "deny"},
        ]))

    def test_browser_not_denied(self):
        self.assertFalse(opencode.browser_denied(None))
        self.assertFalse(opencode.browser_denied([
            {"action": "*", "resource": "*", "effect": "allow"},
        ]))


class RecorderTest(unittest.TestCase):
    def test_ipc_without_connection(self):
        self.assertFalse(recorder.send_ipc("stop"))


if __name__ == "__main__":
    unittest.main()
