<p align="center"><a href="README.md">中文</a></p>

# WhisperingTime · 印迹

Revisit the traces of your life, and add a memory when you want to.

The macOS 26+ SwiftUI prototype puts memories first: cards, calendar, a compressed timeline, and an in-app slideshow. Dates are hidden by default; titles and classification are optional. A flexible tree replaces the old fixed theme/group hierarchy.

Prototype records, pictures, audio, on-device transcripts, and scales are stored locally. Real sync, content encryption, production backups, and legacy import are future work. The sync screen explicitly demonstrates proposed behavior.

## Project navigation

- [Product features and design](Docs/产品/产品功能与设计说明.md)
- [Restart plan](Docs/产品/项目重启计划.md)
- [Development guide](Docs/开发/开发指南.md)
- [UI specification](Docs/设计资产/当前界面/UI设计规范.md)
- [SwiftUI prototype verification](Docs/开发/SwiftUI原型验证.md)
- [Original product description](Docs/产品/产品说明.md) and [research archive](Docs/产品/调研/印迹小规模调研.md)
- [Legacy reliability verification](Docs/开发/记录可靠性验证.md) and [legacy backup verification](Docs/开发/备份恢复验证.md): historical Flutter evidence, not SwiftUI guarantees.
- [Native application](App/WhisperingTime/): standalone Xcode project, no third-party packages.
- [Existing Go server](App/engine/) and [legacy protocol](App/proto/): preserved, not connected to the prototype or converted into a relay.
- [Research directory guide](Research/目录说明.md)

Work on `develop`. Application projects belong in `App/`, formal Chinese documents in `Docs/`, research in `Research/`, and ignored build/test artifacts in task-specific `TMP/` folders.
