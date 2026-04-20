# RhythmFactory

> 我们在做一款节拍驱动的工厂解谜游戏。  
> We're building a rhythm-driven factory puzzle game.

[中文](#中文) | [English](#english)

## 中文

### 这是什么

`RhythmFactory` 是我们用 **Godot 4.6** 在做的一款节拍驱动工厂解谜游戏。

我们一直很喜欢工厂游戏里那种“线路终于跑顺了”的感觉，也很喜欢节奏游戏里那种“刚好卡上这一拍”的满足感。这个项目最初就是想把这两种快乐揉在一起。

所以在这里，生产线不是连续滚动的，而是跟着拍点一拍一拍往前走。货物什么时候被送出去，机器什么时候接住它，信号什么时候触发，都会改变这一拍之后会发生什么。对我们来说，`RhythmFactory` 想做的不是一套越来越臃肿的系统，而是一套简单、清楚、但能让人反复琢磨时序和布局的规则。

### 它现在是什么样子

现在的 `RhythmFactory` 还是一个正在成形的原型，但已经有了比较完整的骨架。

- 有按拍点推进的核心结算
- 有传送、压塑、打包、回收、信号这些基础对象
- 有内置关卡，可以直接进入主菜单开始玩
- 也已经有了我们想要的那种冷色像素、霓虹实验室气质

### 我们想要的感觉

如果要用几句话来形容它，我们希望它是这样的：

- 不是拼手速，而是拼时机
- 不是铺很大的图，而是把一小段生产线想明白
- 看起来有点冷、有点机械，但节奏跑起来的时候会很顺
- 规则不复杂，但每多一个对象，组合关系都会变得更有意思

### 现在可以怎么运行

1. 用 **Godot 4.6** 打开仓库根目录下的 `project.godot`
2. 等待资源导入完成
3. 运行项目，进入主菜单
4. 选择内置关卡开始游玩

如果你想继续往下翻，关卡数据在 `levels/`，核心逻辑主要在 `scripts/`。

---

## English

### What This Is

`RhythmFactory` is a rhythm-driven factory puzzle game we're building in **Godot 4.6**.

We love the feeling of finally getting a factory line to run smoothly, and we also love that small moment in rhythm games when everything lands exactly on beat. This project started as an attempt to bring those two feelings together.

So in `RhythmFactory`, the factory does not run as a continuous stream. It advances beat by beat. The moment a cargo moves, the beat a machine accepts it, or the timing of a signal trigger can completely change what happens next. For us, the goal is not to pile on more and more systems. We want a ruleset that stays readable, stays compact, and still gives players plenty to think about in terms of timing and layout.

### What It Looks Like Right Now

`RhythmFactory` is still taking shape, but the core of it is already there.

- A beat-based resolution loop
- Core gameplay objects for transport, pressing, packing, recycling, and signals
- Built-in levels you can launch from the main menu
- The cool-toned pixel, neon-lab atmosphere we want the project to have

### The Feel We're Chasing

If we had to describe the game in a few lines, this is what we're aiming for:

- Less about reaction speed, more about timing
- Less about giant maps, more about understanding one compact production line
- A little cold, a little mechanical, but satisfying once the rhythm clicks
- Simple rules that become more interesting as objects start interacting

### How To Run It

1. Open `project.godot` in **Godot 4.6**
2. Wait for asset import to finish
3. Run the project to enter the main menu
4. Pick one of the built-in levels and start playing

If you want to dig further, the level data lives in `levels/`, and most of the gameplay logic lives in `scripts/`.
