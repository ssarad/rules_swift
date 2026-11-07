"""SDK alias rendering tests without requiring an installed Xcode."""

import io
import unittest

from tools.explicit_modules import scan


class ModuleAliasesTest(unittest.TestCase):
    def test_strict_and_optional_aliases(self):
        output = io.StringIO()
        scan._render_module_aliases(
            {"MacOSX": {"AppKit"}, "iPhoneSimulator": {"UIKit"}}, output
        )
        self.assertEqual(
            output.getvalue(),
            '''
alias(
    name = "AppKit",
    actual = select({
        ":MacOSX_sdk": ":MacOSX_AppKit",
    }),
)

alias(
    name = "optional/AppKit",
    actual = select({
        ":MacOSX_sdk": ":MacOSX_AppKit",
        "//conditions:default": ":_empty_optional_module",
    }),
)

alias(
    name = "UIKit",
    actual = select({
        ":iPhoneSimulator_sdk": ":iPhoneSimulator_UIKit",
    }),
)

alias(
    name = "optional/UIKit",
    actual = select({
        ":iPhoneSimulator_sdk": ":iPhoneSimulator_UIKit",
        "//conditions:default": ":_empty_optional_module",
    }),
)
''',
        )

    def test_device_only_and_multiple_sdk_module(self):
        output = io.StringIO()
        scan._render_module_aliases(
            {
                "iPhoneOS": {"DeviceOnly", "Foundation"},
                "iPhoneSimulator": {"Foundation"},
            },
            output,
        )
        blocks = output.getvalue().split("\nalias(\n")[1:]
        self.assertEqual(len(blocks), 4)
        device_optional = blocks[1]
        self.assertIn('name = "optional/DeviceOnly"', device_optional)
        self.assertNotIn(":iPhoneSimulator_sdk", device_optional)
        self.assertIn('"//conditions:default": ":_empty_optional_module"', device_optional)
        foundation_optional = blocks[3]
        self.assertIn('":iPhoneOS_sdk": ":iPhoneOS_Foundation"', foundation_optional)
        self.assertIn('":iPhoneSimulator_sdk": ":iPhoneSimulator_Foundation"', foundation_optional)

    def test_no_modules(self):
        output = io.StringIO()
        scan._render_module_aliases({}, output)
        self.assertEqual(output.getvalue(), "")


if __name__ == "__main__":
    unittest.main()
