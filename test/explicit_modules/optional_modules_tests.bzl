"""Tests for the public optional SDK dependency contract."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts", "unittest")
load("@optional_test_hub//:optional_sdk_deps.bzl", "optional_sdk_deps")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//swift:providers.bzl", "SwiftInfo")
load("//tools/explicit_modules:optional_module_repo.bzl", "module_catalog", "optional_aliases_build")

def _helper_test_impl(ctx):
    env = unittest.begin(ctx)
    labels = optional_sdk_deps(["UIKit", "NotAnSDKModule", "Foundation", "UIKit", "FutureModule"])
    asserts.equals(env, ["optional/Foundation", "optional/FutureModule", "optional/UIKit"], [label.name for label in labels])
    asserts.true(env, all([label.repo_name == Label("@optional_test_hub//:module_catalog.json").repo_name for label in labels]))
    return unittest.end(env)

def _providers_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    asserts.equals(env, ctx.attr.expected_modules, sorted([module.name for module in target[SwiftInfo].transitive_modules.to_list()]))
    asserts.equals(env, [], target[DefaultInfo].files.to_list())
    asserts.equals(env, [], target[CcInfo].linking_context.linker_inputs.to_list())
    asserts.equals(env, [], target[CcInfo].compilation_context.headers.to_list())
    asserts.equals(env, [], analysistest.target_actions(env))
    return analysistest.end(env)

_provider_attrs = {"expected_modules": attr.string_list()}
_mac_provider_test = analysistest.make(_providers_test_impl, attrs = _provider_attrs, config_settings = {"//command_line_option:platforms": str(Label("//test/explicit_modules:macos"))})
_sim_provider_test = analysistest.make(_providers_test_impl, attrs = _provider_attrs, config_settings = {"//command_line_option:platforms": str(Label("//test/explicit_modules:ios_simulator"))})
_device_provider_test = analysistest.make(_providers_test_impl, attrs = _provider_attrs, config_settings = {"//command_line_option:platforms": str(Label("//test/explicit_modules:ios_device"))})
_helper_test = unittest.make(_helper_test_impl)

def optional_providers_test_suite(name):
    """Check missing-Xcode and missing-SDK fallbacks propagate no fake modules.

    Args:
        name: Prefix for the analysis test targets.
    """
    _mac_provider_test(name = name + "_old_xcode", target_under_test = "@old_optional_sdk//:UIKit", expected_modules = [])
    _mac_provider_test(name = name + "_macos", target_under_test = "@new_optional_sdk//:UIKit", expected_modules = [])
    _sim_provider_test(name = name + "_simulator", target_under_test = "@new_optional_sdk//:UIKit", expected_modules = ["UIKit"])
    _sim_provider_test(name = name + "_device_only_absent", target_under_test = "@new_optional_sdk//:DeviceOnly", expected_modules = [])
    _device_provider_test(name = name + "_device_only_present", target_under_test = "@new_optional_sdk//:DeviceOnly", expected_modules = ["DeviceOnly"])
    _mac_provider_test(name = name + "_unknown", target_under_test = "@new_optional_sdk//:FutureModule", expected_modules = [])
    _mac_provider_test(name = name + "_shared", target_under_test = "@old_optional_sdk//:Foundation", expected_modules = ["Foundation"])

def _catalog_test_impl(ctx):
    env = unittest.begin(ctx)
    asserts.equals(env, {
        "schema_version": 1,
        "modules": ["AppKit", "NewSDKModule", "UIKit"],
    }, module_catalog(["UIKit", "AppKit", "all_modules", "implicit_modules", "all_cross_import_overlays"], ["UIKit", "NewSDKModule"]))
    return unittest.end(env)

def _missing_module_test_impl(ctx):
    env = unittest.begin(ctx)
    asserts.equals(env, """\
load("@rules_swift//swift:swift.bzl", "system_module_group")
package(default_visibility = ["//visibility:public"])
system_module_group(name = "_empty", creates_module = False)
alias(name = "Foundation", actual = "@old_xcode//:optional/Foundation")
alias(name = "NewSDKModule", actual = ":_empty")
""", optional_aliases_build(["Foundation", "NewSDKModule"], ["Foundation"], ["Foundation"], "@old_xcode"))
    return unittest.end(env)

_catalog_test = unittest.make(_catalog_test_impl)
_missing_module_test = unittest.make(_missing_module_test_impl)

def optional_modules_test_suite(name):
    """Exercise the catalog and old-Xcode fallbacks."""
    unittest.suite(name, _catalog_test, _missing_module_test, _helper_test)

def _legacy_probe_impl(_ctx):
    optional_aliases_build(["Foundation"], ["Foundation"], [], "@legacy_xcode")
    return []

_legacy_probe = rule(implementation = _legacy_probe_impl)

def _legacy_error_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "Regenerate it with the current rules_swift scan tool")
    return analysistest.end(env)

_legacy_error_test = analysistest.make(_legacy_error_test_impl, expect_failure = True)

def optional_legacy_test_suite(name):
    """Old vendored definitions fail clearly only when optional deps are used."""
    _legacy_probe(name = name + "_probe", tags = ["manual"])
    _legacy_error_test(name = name, target_under_test = ":" + name + "_probe")
