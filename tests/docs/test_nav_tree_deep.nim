## Tier 1 (ViewModel / pure-helper) M5 corrective deliverable 1 suite --
## dual-target: both `nim c -r` and `nim js -r` must pass.
##
## Proves `src/core/navigation_vm.nim`'s infinite-depth sidebar tree
## (M5 corrective deliverable 1, "not a flat list"): a 3+ level nested
## `section` fixture builds a real recursive `NavSection` tree (not a
## flat run of same-key sections), `toggleNavSection` flips exactly one
## node's collapse state at any depth, and the active route's whole
## ancestor chain auto-expands by default while unrelated branches stay
## collapsed. Also proves `isExternalNavLink`, the pure helper
## `navigation_view.nim`'s external-link-icon/`target=_blank` rendering
## keys off. All of it is exercised through in-memory `NavPage` values --
## no filesystem access anywhere -- so the exact same assertions hold on
## both targets.

import std/unittest
import ../../src/core/navigation_vm

proc deepPages(): seq[NavPage] =
  @[
    NavPage(routePath: "/", title: "Welcome", section: "", order: 0, slug: "index"),
    NavPage(routePath: "/guide/intro", title: "Intro", section: "guide", order: 0, slug: "intro"),
    NavPage(routePath: "/guide/advanced/setup", title: "Setup",
      section: "guide/advanced", order: 0, slug: "setup"),
    NavPage(routePath: "/guide/advanced/tips/pro", title: "Pro Tips",
      section: "guide/advanced/tips", order: 0, slug: "pro"),
    NavPage(routePath: "/guide/advanced/tips/basic", title: "Basic Tips",
      section: "guide/advanced/tips", order: 1, slug: "basic"),
    NavPage(routePath: "/reference/api", title: "API", section: "reference", order: 0, slug: "api"),
  ]

suite "docs navigation ViewModel -- buildSidebar infinite-depth tree (Tier 1, dual-target)":
  test "buildSidebar nests a 3+ level section path as a real recursive tree, not a flat run":
    let sidebar = buildSidebar(deepPages(), "/nowhere")
    # Top level: "" (ungrouped), "guide", "reference" -- "guide/advanced"
    # and "guide/advanced/tips" are NOT separate top-level entries.
    check sidebar.sections.len == 3
    check sidebar.sections[0].key == ""
    check sidebar.sections[0].items.len == 1
    check sidebar.sections[0].items[0].title == "Welcome"
    check sidebar.sections[0].children.len == 0

    let guide = sidebar.sections[1]
    check guide.key == "guide"
    check guide.title == "Guide"
    check guide.items.len == 1
    check guide.items[0].title == "Intro"
    check guide.children.len == 1

    let advanced = guide.children[0]
    check advanced.key == "guide/advanced"
    check advanced.title == "Advanced" # own segment only, not "Guide Advanced"
    check advanced.items.len == 1
    check advanced.items[0].title == "Setup"
    check advanced.children.len == 1

    let tips = advanced.children[0]
    check tips.key == "guide/advanced/tips"
    check tips.title == "Tips"
    check tips.items.len == 2
    check tips.items[0].title == "Pro Tips"
    check tips.items[1].title == "Basic Tips"
    check tips.children.len == 0

    let reference = sidebar.sections[2]
    check reference.key == "reference"
    check reference.title == "Reference"
    check reference.children.len == 0

  test "buildSidebar auto-expands the active route's whole ancestor chain, leaving unrelated branches collapsed":
    let sidebar = buildSidebar(deepPages(), "/guide/advanced/tips/pro")
    let guide = sidebar.sections[1]
    check guide.key == "guide"
    check guide.isExpanded == true # ancestor of the active leaf
    let advanced = guide.children[0]
    check advanced.isExpanded == true # ancestor of the active leaf
    let tips = advanced.children[0]
    check tips.isExpanded == true # direct parent of the active leaf
    let reference = sidebar.sections[2]
    check reference.isExpanded == false # unrelated branch, no active descendant

  test "buildSidebar collapses every real section when no page is active":
    let sidebar = buildSidebar(deepPages(), "/nowhere")
    check sidebar.sections[0].isExpanded == true # ungrouped top level, always open
    let guide = sidebar.sections[1]
    check guide.isExpanded == false
    check guide.children[0].isExpanded == false
    check guide.children[0].children[0].isExpanded == false
    check sidebar.sections[2].isExpanded == false

suite "docs navigation ViewModel -- toggleNavSection (Tier 1, dual-target)":
  test "toggleNavSection flips exactly the node matching key, at any depth, leaving the rest untouched":
    let sidebar = buildSidebar(deepPages(), "/nowhere")
    check sidebar.sections[1].isExpanded == false # "guide"
    check sidebar.sections[1].children[0].isExpanded == false # "guide/advanced"

    let toggled = toggleNavSection(sidebar, "guide/advanced")
    check toggled.sections[1].isExpanded == false # untouched sibling/ancestor
    check toggled.sections[1].children[0].isExpanded == true # the toggled node
    check toggled.sections[1].children[0].children[0].isExpanded == false # untouched child
    check toggled.sections[2].isExpanded == false # untouched unrelated top section

  test "toggleNavSection is a pure, non-mutating transform: the input sidebar is unchanged":
    let sidebar = buildSidebar(deepPages(), "/nowhere")
    discard toggleNavSection(sidebar, "guide")
    check sidebar.sections[1].isExpanded == false

  test "toggleNavSection toggling the same key twice returns to the original state":
    let sidebar = buildSidebar(deepPages(), "/nowhere")
    let once = toggleNavSection(sidebar, "guide/advanced/tips")
    let twice = toggleNavSection(once, "guide/advanced/tips")
    check twice == sidebar

  test "toggleNavSection on an unknown key is a no-op":
    let sidebar = buildSidebar(deepPages(), "/nowhere")
    let toggled = toggleNavSection(sidebar, "does/not/exist")
    check toggled == sidebar

suite "docs navigation ViewModel -- isExternalNavLink (Tier 1, dual-target)":
  test "an absolute in-site path is never external":
    check isExternalNavLink("/guide/intro") == false
    check isExternalNavLink("/") == false

  test "an off-site URL, protocol-relative link, or non-'/'-leading href is external":
    check isExternalNavLink("https://example.com/docs") == true
    check isExternalNavLink("//cdn.example.com/asset") == true
    check isExternalNavLink("mailto:hello@example.com") == true
    check isExternalNavLink("") == true
