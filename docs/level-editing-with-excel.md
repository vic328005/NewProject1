# Excel 关卡编辑方案

## 目标

为当前项目保留一条简单稳定的关卡编辑链路：

1. 使用 Excel 编辑二维离散地图。
2. 通过外部转换工具将表格数据编译为 JSON。
3. 在 Godot 运行时加载 JSON，并实例化 `belt`、`cargo`、`producer`、`recycler`。

核心分工保持不变：

- Excel 负责编辑体验。
- JSON 负责运行时数据。
- 编译工具负责校验、规范化和输出。

## 当前运行时模型

项目当前只使用“稀疏格子 + 分层存储”的模型，不再保留独立 `entities` 数组：

- `World` 维护 `cargo_layer`、`belt_layer`、`producer_layer`、`recycler_layer`
- `MapLayer` 使用 `Vector2i -> Variant` 存储非空格子
- 关卡 JSON 只保留顶层 `cells` 数组

这意味着 Excel 侧也应直接围绕格子内容来设计，不要再拆出单独的 `Entities` sheet。

## 推荐的数据编辑结构

推荐一个 Excel 文件对应一个关卡，包含以下两个工作表：

1. `Grid`
2. `LevelMeta`

### Sheet: Grid

用于编辑二维地图，是主编辑界面。

建议规则：

- 行列直接对应游戏格子坐标。
- 空白单元格表示该格子没有内容。
- 同一格支持多个对象，使用 `|` 分隔。
- 常规内容使用受约束的短语法，不直接编辑完整 JSON。

建议的单元格语法：

```text
belt:R:S:2
cargo:CARGO_1
belt:U:L:1|cargo:CARGO_2
producer:R:4:CARGO_1
belt:R:S:2|recycler
```

字段说明：

- `belt:<朝向>:<模式>:<节拍间隔>`
- `cargo:<类型>`
- `producer:<朝向>:<节拍间隔>:<货物类型>`
- `recycler`

建议枚举值：

- 朝向：`U` `R` `D` `L`
- 皮带模式：`S` `L` `R`
  - `S` = straight
  - `L` = left turn
  - `R` = right turn
- 货物类型：`CARGO_1` `CARGO_2` `CARGO_3`

当前运行时约定：

- `belt`、`producer`、`recycler` 允许共格。
- `cargo` 每格最多一个。
- 每拍结算顺序固定为：`producer -> belt -> recycler`。

### Sheet: LevelMeta

用于描述关卡级配置。

建议字段：

```text
key | value
```

示例：

```text
level_id | tutorial_01
display_name | 第一关
beat_bpm | 120
```

## 推荐的导出 JSON 结构

运行时 JSON 建议采用稀疏存储，只记录非空格子。

示例：

```json
{
  "level_id": "tutorial_01",
  "display_name": "第一关",
  "beat_bpm": 120,
  "cells": [
    {
      "x": 0,
      "y": 0,
      "belt": {
        "facing": "RIGHT",
        "turn_mode": "STRAIGHT",
        "beat_interval": 2
      },
      "producer": {
        "facing": "RIGHT",
        "beat_interval": 4,
        "cargo_type": "CARGO_1"
      }
    },
    {
      "x": 1,
      "y": 0,
      "belt": {
        "facing": "UP",
        "turn_mode": "LEFT",
        "beat_interval": 1
      },
      "cargo": {
        "type": "CARGO_2"
      }
    },
    {
      "x": 2,
      "y": 0,
      "recycler": {}
    }
  ]
}
```

映射关系：

- `x`, `y` -> `Vector2i`
- `x`, `y` 允许任意整数坐标（包含负数）
- `belt.facing` -> `Belt.Direction`
- `belt.turn_mode` -> `Belt.TurnMode`
- `belt.beat_interval` -> `Belt.beat_interval`
- `cargo.type` -> `Cargo.cargo_type`
- `producer.facing` -> `Producer.Direction`
- `producer.beat_interval` -> `Producer.beat_interval`
- `producer.cargo_type` -> `Producer.cargo_type`
- `recycler` -> `Recycler` 占位设施，v1 无额外参数

## 编译工具职责

外部转换工具建议只做一件事：把 Excel 编译成规范 JSON。

推荐职责：

1. 读取 Excel 工作簿
2. 解析 `Grid` 中的简写语法
3. 读取 `LevelMeta`
4. 做数据校验
5. 输出稳定 JSON

建议至少做以下校验：

- 单元格语法是否合法
- `x` / `y` 是否为整数
- `belt` 朝向和模式是否属于允许枚举
- `producer` 朝向和货物类型是否属于允许枚举
- `beat_interval` 是否为正整数
- 同一格是否出现重复的同类对象

如果校验失败，编译工具应直接报错，不生成输出文件。

## 实现边界

为了保持当前仓库简洁，当前阶段建议只支持以下内容：

1. `belt`
2. `cargo`
3. `producer`
4. `recycler`
5. `level meta`

先保持最小闭环：

1. Excel 填表
2. 编译得到 JSON
3. Godot 成功加载 JSON
4. 关卡能按节拍运行

等这条链路稳定后，再考虑更复杂的目标、计数条件或特殊事件系统。
