<p align="center"><a href="README_en.md"> Engine</a></p>

# 枫迹

生活不只是日复一日，更是步步印迹

## 项目导航

参考 PianoRoam 的目录组织，应用工程、研发资料、正式文档和临时产物分别放在 `App/`、`Research/`、`Docs/` 和 `TMP/`。

```text
WhisperingTime/
├── App/
│   ├── WhisperingTime/     # Flutter 应用工程
│   ├── engine/             # Go 服务端与数据库建表脚本
│   └── proto/              # 协议定义
├── Docs/
│   ├── 开发/               # 开发与运行说明
│   └── 设计资产/
│       ├── 应用标志/       # 图标设计源文件
│       └── 当前界面/       # 当前 Flutter UI 设计规范
├── Research/               # 研发资料与实验记录
├── TMP/                    # 按任务分类的临时产物（Git 忽略）
├── .github/                # GitHub 配置
├── AGENTS.md               # 协作规则
├── README.md
├── README_en.md
└── LICENSE
```

- [开发指南](Docs/开发/开发指南.md)：Flutter 和 Go 的开发、验证与构建命令。
- [UI设计规范](Docs/设计资产/当前界面/UI设计规范.md)：温暖极简主题、布局、组件和验证范围。
- [Flutter 应用工程](App/WhisperingTime/)：在此目录执行 Flutter 命令。
- [Go 服务端](App/engine/)：在此目录执行 Go 命令；数据库建表脚本为 `ddl.sql`。
- [协议定义](App/proto/)：客户端与服务端使用的协议源文件。
- [应用标志源文件](Docs/设计资产/应用标志/icon.psd)：运行时 PNG 资源保留在 Flutter 工程中。
- [研发目录说明](Research/目录说明.md)：研发资料的归档约定。
