<p align="center"><a href="README.md">中文</a></p>

# WhisperingTime

Life is not just days passing, but the footprints of our progress.

## Project navigation

The repository follows PianoRoam's top-level layout: `App/` for application projects, `Research/` for research materials, `Docs/` for documentation and design assets, and `TMP/` for temporary task outputs.

- [Development guide](Docs/开发/开发指南.md) (Chinese): Flutter and Go development, validation, and build commands.
- [Flutter application](App/WhisperingTime/): run Flutter commands from this directory.
- [Go server](App/engine/): run Go commands from this directory; `ddl.sql` contains the database schema.
- [Protocol definitions](App/proto/): shared protocol source files.
- [Application icon source](Docs/设计资产/应用标志/icon.psd): runtime PNG assets remain in the Flutter project.
- [Research directory guide](Research/目录说明.md) (Chinese): conventions for research materials.

Temporary outputs belong in a task-specific subdirectory of `TMP/` and are ignored by Git. The root keeps shared entry files such as `AGENTS.md`, both READMEs, `LICENSE`, and GitHub configuration.
