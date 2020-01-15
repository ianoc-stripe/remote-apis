"""Repository rules and macros which are expected to be called from WORKSPACE
file of either bazel_remote_apis itself or any third_party repository which
consumes bazel_remote_apis as its dependency.

This is adapted from
https://github.com/googleapis/googleapis/blob/master/repository_rules.bzl
"""


def _switched_rules_impl(ctx):
    go_deps = """
load("@bazel_gazelle//:deps.bzl", "gazelle_dependencies", "go_repository")
load("@io_bazel_rules_go//go:deps.bzl", "go_register_toolchains", "go_rules_dependencies")

def _maybe(repo_rule, name, **kwargs):
    if name not in native.existing_rules():
        repo_rule(name = name, **kwargs)

def load_deps():
    # Load dependencies needed to depend on RE API for Go
    go_rules_dependencies()
    go_register_toolchains()
    gazelle_dependencies()
    _maybe(
        go_repository,
        name = "com_github_golang_protobuf",
        importpath = "github.com/golang/protobuf",
        tag = "v1.3.2",
    )
    _maybe(
        go_repository,
        name = "org_golang_google_grpc",
        build_file_proto_mode = "disable",
        importpath = "google.golang.org/grpc",
        sum = "h1:J0UbZOIrCAl+fpTOf8YLs4dJo8L/owV4LYVtAXQoPkw=",
        version = "v1.22.0",
    )
    _maybe(
        go_repository,
        name = "org_golang_x_net",
        importpath = "golang.org/x/net",
        sum = "h1:oWX7TPOiFAMXLq8o0ikBYfCJVlRHBcsciT5bXOrH628=",
        version = "v0.0.0-20190311183353-d8887717615a",
    )
    _maybe(
        go_repository,
        name = "org_golang_x_text",
        importpath = "golang.org/x/text",
        sum = "h1:g61tztE5qeGQ89tm6NTjjM9VPIm088od1l6aSorWRWg=",
        version = "v0.3.0",
    )
"""
    no_go_deps = """
def load_deps():
    pass
    """

    disabled_rule_script = """
def {rule_name}(**kwargs):
    pass
"""
    enabled_native_rule_script = """
{rule_name} = {native_rule_name}
"""
    enabled_rule_script = """
load("{file_label}", _{rule_name} = "{rule_name}")
"""
    elabled_rule_scrip_alias = """
{rule_name} = _{rule_name}
"""

    load_rules = []  # load() must go before everything else in .bzl files since Bazel 0.25.0
    rules = []

    for rule_name, value in ctx.attr.rules.items():
        if not value:
            rules.append(disabled_rule_script.format(rule_name = rule_name))
        elif value.startswith("@"):
            load_rules.append(enabled_rule_script.format(file_label = value, rule_name = rule_name))
            rules.append(elabled_rule_scrip_alias.format(rule_name = rule_name))
        elif value.startswith("native."):
            rules.append(
                enabled_native_rule_script.format(rule_name = rule_name, native_rule_name = value),
            )
        else:
            rules.append(value)

    ctx.file("BUILD.bazel", "")
    ctx.file("imports.bzl", "".join(load_rules + rules))

    if(ctx.attr.enable_go):
        ctx.file("deps.bzl", go_deps)
    else:
        ctx.file("deps.bzl", no_go_deps)

switched_rules = repository_rule(
    implementation = _switched_rules_impl,
    attrs = {
        "rules": attr.string_dict(
            allow_empty = True,
            mandatory = False,
            default = {},
        ),
        "enable_go": attr.bool(
            mandatory = False,
            default = False,
        ),
    },
)

def switched_rules_by_language(
        name,
        java = False,
        go = False,
        cc = False,
        rules_override = {}):
    """Switches rules in the generated imports.bzl between no-op and the actual
    implementation.

    This defines which language-specific rules should be enabled during the
    build. All non-enabled language-specific rules will default to no-op
    implementations.

    For example, to use this rule and enable Java and Go rules, add the
    following in the external repository which imports bazel_remote_apis
    repository and its corresponding dependencies:

        load("@bazel_remote_apis//:repository_rules.bzl", "switched_rules_by_language")

        switched_rules_by_language(
            name = "bazel_remote_apis_imports",
            go = True,
            java = True,
        )

    Then import e.g. "go_library" from @bazel_remote_apis_imports in your BUILD files:

        load("@bazel_remote_apis_imports//:imports.bzl", "go_library")

    Note, for build to work you must also import the language-specific transitive dependencies.

    Args:
        name (str): name of a target, is expected to be "bazel_remote_apis_imports".
        java (bool): Enable Java specific rules. False by default.
        go (bool): Enable Go specific rules. False by default.
        cc (bool): Enable C++ specific rules. False by default.
        rules_override (dict): Custom rule overrides (for advanced usage).
    """

    rules = {}

    rules["java_proto_library"] = _switch(
        java,
        "native.java_proto_library",
    )

    rules["go_proto_library"] = _switch(
        go,
        "@io_bazel_rules_go//proto:def.bzl",
    )
    rules["go_library"] = _switch(
        go,
        "@io_bazel_rules_go//go:def.bzl",
    )

    rules["cc_grpc_library"] = _switch(
        cc,
        "@com_github_grpc_grpc//bazel:cc_grpc_library.bzl",
    )

    rules.update(rules_override)

    switched_rules(
        name = name,
        rules = rules,
        enable_go = go,
    )



def _switch(enabled, enabled_value):
    return enabled_value if enabled else ""
