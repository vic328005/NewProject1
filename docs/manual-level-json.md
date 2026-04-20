# 手动配置关卡 JSON 说明

## 适用范围

这份文档说明当前项目里“关卡 / 场景数据 JSON”手动配置时的真实格式和行为，面向直接编辑 JSON 的人。

当前默认入口在 `scripts/config.gd`：

```gdscript
var start_level_path: String = "res://levels/level03.json"
```

运行时解析和实例化规则以下面两个脚本为准：

- `scripts/level_data.gd`
- `scripts/level_loader.gd`

配套的标准 JSON Schema 放在：

- `docs/manual-level-json.schema.json`

文档只描述当前代码已经支持的内容，不包含 Excel 流程，也不包含未来设计。

补充说明：

- 这份 schema 以标准 JSON Schema Draft 2020-12 编写
- 它已经覆盖当前大部分字段和组合校验
- 但“`cells` 中 `x/y` 组合唯一”以及“`recycler.targets` 中 `product_type` 去空白并转大写后仍需唯一”这两条，标准 JSON Schema 本身无法精确表达，最终仍以运行时代码校验为准

## 整体结构

关卡文件的根节点必须是一个 JSON object，当前允许的顶层字段只有：

- `level_id`
- `display_name`
- `beat_bpm`
- `failure_beat_limit`
- `cells`

任意未知字段都会直接报错，文件不会被加载。

最小示例：

```json
{
  "level_id": "level01",
  "display_name": "示例关卡",
  "cells": [
    {
      "x": 0,
      "y": 0,
      "belt": {
        "input_direction": "RIGHT",
        "output_direction": "RIGHT",
        "beat_interval": 2
      }
    }
  ]
}
```

### 顶层字段

#### `level_id`

- 必填
- 必须是非空字符串
- 只做字符串非空校验，不要求唯一

#### `display_name`

- 必填
- 必须是非空字符串

#### `beat_bpm`

- 可选
- 必须是数字
- 必须大于 `0`
- 省略时默认值为 `160.0`

补充说明：

- `LevelData` 校验层只要求它大于 `0`
- 真正进入节拍器后，`BeatConductor` 还会把 BPM 限制在 `1` 到 `240` 之间

#### `failure_beat_limit`

- 可选
- 必须是正整数
- 省略时默认值为 `60`

运行语义：

- 当前拍数达到这个值后，如果关卡仍未完成，会直接判定失败
- 结果面板里的 `当前拍数 x / y` 中，后面的 `y` 也会显示这个值

#### `cells`

- 必填
- 必须是数组
- 使用稀疏存储，只写非空格子
- 每一项都必须是 object

## `cells` 规则

每个 cell 当前允许的字段只有：

- `x`
- `y`
- `belt`
- `item`
- `producer`
- `recycler`
- `signal_tower`
- `press_machine`
- `packer`

### 基础规则

#### `x` / `y`

- 必填
- 必须是整数
- 允许负数
- 全局坐标不能重复

重复坐标会报错，例如：

```text
duplicate cell coordinates found at (3, 5)
```

### 组合限制

一个 cell 必须至少包含一个玩法对象。下面这些规则会在加载时直接校验：

- `signal_tower` 必须独占一个格子，不能和任何其他对象共格
- `belt` / `producer` / `recycler` / `press_machine` / `packer` 这五类里，每格最多只能有一个
- `item` 可以单独存在
- `item` 可以和 `belt` 共格
- `item` 可以和 `press_machine` 共格，但此时 `item.kind` 必须是 `CARGO`
- `item` 可以和 `packer` 共格，但此时 `item.kind` 必须是 `CARGO`

合法组合示例：

```json
{
  "x": 1,
  "y": 2,
  "item": {
    "kind": "CARGO",
    "type": "A"
  }
}
```

```json
{
  "x": 3,
  "y": 2,
  "belt": {
    "input_direction": "RIGHT",
    "output_direction": "UP",
    "beat_interval": 1
  },
  "item": {
    "kind": "CARGO",
    "type": "B"
  }
}
```

```json
{
  "x": 5,
  "y": 2,
  "press_machine": {
    "facing": "RIGHT",
    "cargo_type": "C",
    "beat_interval": 2
  },
  "item": {
    "kind": "CARGO",
    "type": "A"
  }
}
```

非法组合示例：

- `signal_tower` 和任何其他对象共格
- 同时写 `belt` 和 `producer`
- `press_machine` 和 `item.kind = PRODUCT` 共格
- `packer` 和 `item.kind = PRODUCT` 共格

## 各对象字段说明

### `belt`

`belt` 必须是 object，当前只允许以下字段：

- `input_direction`
- `output_direction`
- `beat_interval`

示例：

```json
{
  "belt": {
    "input_direction": "RIGHT",
    "output_direction": "UP",
    "beat_interval": 1
  }
}
```

字段规则：

- `input_direction`：必填，非空字符串，只能是 `UP` / `RIGHT` / `DOWN` / `LEFT`
- `output_direction`：必填，非空字符串，只能是 `UP` / `RIGHT` / `DOWN` / `LEFT`
- `beat_interval`：必填，正整数，且只能是 `1` 或 `2`

额外限制：

- `input_direction` 和 `output_direction` 不能相反
- 两者只能“相同”或“垂直”
- 也就是只支持直线带和转弯带，不支持 U 形回头

运行语义：

- 传送带只在触发拍运输物体
- 只有 `item.flow_direction == belt.input_direction` 时，物体才会被这条带子接走
- 运输成功后，物体的流向会被改成 `output_direction`
- 如果初始 `item` 和 `belt` 同格，关卡加载时会把该 `item` 的初始流向设置成 `belt.input_direction`

### `item`

`item` 必须是 object，当前只允许以下字段：

- `kind`
- `type`

示例：

```json
{
  "item": {
    "kind": "PRODUCT",
    "type": "C"
  }
}
```

字段规则：

- `kind`：必填，非空字符串，只能是 `CARGO` 或 `PRODUCT`
- `type`：必填，非空字符串，只能是 `A` / `B` / `C`

归一化规则：

- `kind` 会先去掉首尾空白，再转成大写
- `type` 会先去掉首尾空白，再转成大写

运行语义：

- `CARGO` 表示原料 / 中间态
- `PRODUCT` 表示打包后的成品
- 只有 `PRODUCT` 且类型命中 `recycler.targets` 时，才会计入回收目标

### `producer`

`producer` 必须是 object，当前只允许以下字段：

- `facing`
- `beat_interval`
- `production_sequence`

示例：

```json
{
  "producer": {
    "facing": "RIGHT",
    "beat_interval": 3,
    "production_sequence": ["A", "B", "C", "A"]
  }
}
```

字段规则：

- `facing`：必填，非空字符串，只能是 `UP` / `RIGHT` / `DOWN` / `LEFT`
- `beat_interval`：必填，正整数，当前代码没有额外上限
- `production_sequence`：必填，数组，数组元素必须是字符串，且只能是 `A` / `B` / `C`

运行语义：

- 生产机在满足自己节拍条件的拍点上，准备下一份原料
- 原料不会在同一拍立刻落地，而是进入“待出料”状态
- 真正出料要等到下一拍的机器出料阶段
- 出料方向由 `facing` 决定，目标格是机器正前方一格
- `production_sequence` 用完后就不会继续生产

### `recycler`

`recycler` 必须是 object，当前只允许以下字段：

- `targets`

示例：

```json
{
  "recycler": {
    "targets": [
      {
        "product_type": "A",
        "required_count": 5
      },
      {
        "product_type": "B",
        "required_count": 3
      }
    ]
  }
}
```

`targets` 规则：

- 必填
- 必须是数组
- 不能为空数组

每个 target 当前只允许以下字段：

- `product_type`
- `required_count`

target 字段规则：

- `product_type`：必填，非空字符串，只能是 `A` / `B` / `C`
- `required_count`：必填，正整数
- 同一个 `recycler` 内，`product_type` 不能重复

运行语义：

- 如果进入回收机的是 `PRODUCT`，且类型正好在目标列表里，才会计入目标进度
- 不符合目标的 `PRODUCT` 会被销毁，但不计入目标
- `CARGO` 进入回收机也会被销毁，但不计入目标
- 游戏是否通关，依赖所有回收机的目标是否全部完成

### `signal_tower`

`signal_tower` 必须是 object，当前只允许以下字段：

- `max_steps`

示例：

```json
{
  "signal_tower": {
    "max_steps": 10
  }
}
```

字段规则：

- `max_steps`：可选，正整数
- 省略时使用脚本默认值 `10`

运行语义：

- 信号塔不会每拍自动发射信号
- 当前实现里，它监听 `metronome_hit` 事件
- `metronome_hit` 现在由 `scripts/ui/metronome_panel.gd` 在玩家按下任意键或鼠标左右键时发出
- 信号波创建后会立刻写入 `signal_layer`
- 后续每次拍点结算结束时，信号波再推进一圈，直到超过 `max_steps`

### `press_machine`

`press_machine` 必须是 object，当前只允许以下字段：

- `facing`
- `cargo_type`
- `beat_interval`
- `transport_beat_interval`

示例：

```json
{
  "press_machine": {
    "facing": "RIGHT",
    "cargo_type": "B",
    "beat_interval": 2,
    "transport_beat_interval": 1
  }
}
```

字段规则：

- `facing`：必填，非空字符串，只能是 `UP` / `RIGHT` / `DOWN` / `LEFT`
- `cargo_type`：必填，非空字符串，只能是 `A` / `B` / `C`
- `beat_interval`：必填，正整数，且只能是 `1` 或 `2`
- `transport_beat_interval`：可选，正整数，且只能是 `1` 或 `2`

运行语义：

- 压塑机正前方一格是出料目标格
- 这里的“触发”指当前格子收到信号，且当前拍满足 `beat_interval`
- 未触发时按直通处理；若配置了 `transport_beat_interval`，就按该节拍运输
- 省略 `transport_beat_interval` 时，直通节奏默认仍是“每 2 拍一次”
- 触发且空闲时，只接收 `CARGO`
- 触发但机器正忙时，新进入的 `CARGO` 会被直接销毁
- 开始压塑后，机器会在内部把持有物体的类型改成 `cargo_type`
- 改型完成后不会同拍落地，而是下一拍再出料

### `packer`

`packer` 必须是 object，当前只允许以下字段：

- `facing`
- `transport_beat_interval`

示例：

```json
{
  "packer": {
    "facing": "RIGHT",
    "transport_beat_interval": 1
  }
}
```

字段规则：

- `facing`：必填，非空字符串，只能是 `UP` / `RIGHT` / `DOWN` / `LEFT`
- `transport_beat_interval`：可选，正整数，且只能是 `1` 或 `2`

运行语义：

- 打包机只有在收到信号时才会吃入 `CARGO`
- 打包机没有自己的 `beat_interval` 字段，只由是否收到信号决定是否触发
- 机器忙碌时，如果又有物体进入，会直接销毁该物体
- 吃入后内部处理一拍
- 下一拍出料时，生成同类型的 `PRODUCT`
- 出料方向由 `facing` 决定
- 未触发时按直通处理；若配置了 `transport_beat_interval`，就按该节拍运输
- 省略 `transport_beat_interval` 时，直通节奏默认仍是“每 2 拍一次”

## 当前拍点结算顺序

当前代码的实际结算顺序以 `scripts/world/world_simulation.gd` 为准：

1. 处理输入
2. 更新机器内部状态
3. 处理机器出料
4. 处理场上运输
5. 推进信号波

这只是当前实现的真实行为说明，不代表仓库里的目标设计文档。  
如果其他说明和这里冲突，手动配置 JSON 时应以当前代码为准。

### 这对手配数据的直接影响

- 机器“吃入”和“出料”不是同一阶段
- 生产机、压塑机、打包机的结果都存在“晚一拍真正落地”的情况
- 信号波的推进发生在拍点结算末尾，不是在开头
- 因为出料和运输是分开的，所以同拍是否能继续被后面的对象接住，要以当前结算顺序判断，不能按直觉想当然

## 常见配置错误

### 1. 出现未知字段

所有层级都严格限制字段名。比如下面这些都会报错：

- 顶层多写 `version`
- `belt` 里多写 `speed`
- `producer` 里多写 `cargo_type`

### 2. 坐标重复

两个 cell 不能使用同一组 `x` / `y`。

### 3. 方向值非法

方向只能写：

- `UP`
- `RIGHT`
- `DOWN`
- `LEFT`

写成 `R`、`Top`、`Rightward` 都不行。

### 4. 类型值非法

当前货物 / 产品类型只能写：

- `A`
- `B`
- `C`

写成 `D`、`cargo_a`、`1` 都不行。

### 5. 传送带输入输出相反

下面这种 U 形回头配置会报错：

```json
{
  "belt": {
    "input_direction": "LEFT",
    "output_direction": "RIGHT",
    "beat_interval": 2
  }
}
```

### 6. `signal_tower` 没有独占格子

`signal_tower` 不能和 `belt`、`item`、`producer`、`recycler`、`press_machine`、`packer` 中任何一个共格。

### 7. 同格放了多个 machine

下面这些都不允许：

- `belt` + `producer`
- `producer` + `recycler`
- `press_machine` + `packer`

### 8. `press_machine` / `packer` 与 `PRODUCT` 共格

如果一个格子里同时写了机器和 `item`，而 `item.kind` 是 `PRODUCT`，加载会直接失败。

## 完整示例

下面这份示例基于当前仓库里的 `levels/level03.json`，加上了解释说明。  
示例中的注释只是文档说明，真实 JSON 文件里不能写注释。

```jsonc
{
  "level_id": "level03",
  "display_name": "生产打包产线",
  "beat_bpm": 120,
  "failure_beat_limit": 60,
  "cells": [
    {
      "x": 5,
      "y": 8,
      "producer": {
        "facing": "RIGHT",
        "beat_interval": 3,
        "production_sequence": [
          "A", "B", "C", "A", "B", "C", "A", "B", "C", "A",
          "B", "C", "A", "B", "C", "A", "B", "C", "A", "B"
        ]
      }
    },
    {
      "x": 6,
      "y": 8,
      "belt": {
        "input_direction": "RIGHT",
        "output_direction": "RIGHT",
        "beat_interval": 2
      }
    },
    {
      "x": 7,
      "y": 8,
      "belt": {
        "input_direction": "RIGHT",
        "output_direction": "RIGHT",
        "beat_interval": 2
      }
    },
    {
      "x": 8,
      "y": 8,
      "press_machine": {
        "facing": "RIGHT",
        "cargo_type": "B",
        "beat_interval": 2
      }
    },
    {
      "x": 9,
      "y": 8,
      "packer": {
        "facing": "RIGHT"
      }
    },
    {
      "x": 10,
      "y": 8,
      "belt": {
        "input_direction": "RIGHT",
        "output_direction": "RIGHT",
        "beat_interval": 2
      }
    },
    {
      "x": 11,
      "y": 8,
      "belt": {
        "input_direction": "RIGHT",
        "output_direction": "RIGHT",
        "beat_interval": 2
      }
    },
    {
      "x": 12,
      "y": 8,
      "recycler": {
        "targets": [
          {
            "product_type": "A",
            "required_count": 7
          },
          {
            "product_type": "B",
            "required_count": 7
          },
          {
            "product_type": "C",
            "required_count": 6
          }
        ]
      }
    },
    {
      "x": 8,
      "y": 13,
      "signal_tower": {
        "max_steps": 10
      }
    }
  ]
}
```

这份配置表达的是一条很直接的链路：

- 生产机按顺序生产 `A/B/C`
- 原料沿传送带向右移动
- 压塑机把经过的原料压成指定类型
- 打包机在收到信号时把 `CARGO` 打成 `PRODUCT`
- 成品继续向右进入回收机
- 回收机按目标统计 `A/B/C` 三种成品数量

## 手写 JSON 前的快速检查清单

- 根节点是不是 object
- 顶层字段是不是只用了允许的五个
- `level_id` / `display_name` 是否非空
- `failure_beat_limit` 如果填写了，是否为正整数
- `cells` 是否只包含非空格
- 坐标是否重复
- 是否错误地把多个 machine 写进同一格
- 是否错误地让 `signal_tower` 与别的对象共格
- 方向是否只写了 `UP/RIGHT/DOWN/LEFT`
- 类型是否只写了 `A/B/C`
- `press_machine` / `packer` 同格 `item` 是否仍是 `CARGO`
