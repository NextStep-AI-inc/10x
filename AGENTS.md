# 10x — agent notes

## `10x.xcodeproj` is generated. Never hand-edit it.

Add Swift files under `App/` or `Tests/`, then regenerate:

```bash
ruby scripts/generate_xcodeproj.rb
```

The generator globs the source tree, so new files are picked up automatically.
Editing `project.pbxproj` by hand — including inventing UUIDs to add a file —
produces entries the generator does not own and silently loses them on the next
run.

Generation is byte-reproducible: the same source tree yields the same project
file from any checkout path, and adding one Swift file changes 4 lines. That
holds only on **xcodeproj 1.27.0** (pinned in `Gemfile`); every release ships
different default build settings, which change every object UUID. The script
asserts the version and aborts rather than churning the file.

**Merge conflicts in `project.pbxproj` are never resolved by hand.** Take either
side, then re-run the generator and commit its output.
