# PMSM 中性点升压充电 Simulink 仿真模型 - 实施计划

## 背景与目标

搭建一个利用 PMSM 中性点进行 DC-DC 升压充电的 Simulink 仿真模型。拓扑为：

**400V DC 充电桩 → LC 输入滤波 → PMSM 中性点 → 三相绕组（作升压电感）→ 三相逆变器（同步整流 Boost）→ 800V DC-Link → 高压电池**

核心原理：电机静止时三相绕组为纯电感，中性点接输入电源，逆变器作三相交错 Boost 开关，将 400V 升至 800V 给电池充电。这是集成式车载充电器（OBC）的典型拓扑。

## 已实现架构

### 1. 主电路拓扑（SimPowerSystems）

```
  DC_Charger(400V) → Lin_filter(0.5mH) → 中性点 ┬→ L1(0.15mH) → I1_sense → Inverter(A) ┐
                                                   ├→ L2(0.15mH) → I2_sense → Inverter(B)  │
                                                   ├→ L3(0.15mH) → I3_sense → Inverter(C)  │
                                              Cin_filter(500µF)                              │
                                                   │                          DC+ ───────────┘
                                                 GND_in                                      │
                                                                    ┌────────────────────────┘
                                                                    ├→ Cdc_link(2000µF)
                                                                    ├→ Vdc_sense
                                                                    ├→ Battery_V(800V) → R_batt(0.05Ω)
                                                                    └→ GND_out
```

- **库**：SimPowerSystems (`sps_lib`)，非 Simscape Electrical
- **PMSM**：用三个独立电感（Series RLC Branch, L=0.15mH）等效三相绕组，中性点为公共连接点
- **逆变器**：Universal Bridge, 3-arm MOSFET, 20kHz
- **输入滤波**：Lin_filter 0.5mH + Cin_filter 500µF (DC_Charger 侧)
- **电池**：800V 理想电压源 + 0.05Ω 内阻（可替换为 Simscape Battery）
- **Solver**：ode23tb，MaxStep=1µs，ZeroCrossAlgorithm=Adaptive

### 2. 控制算法

```
  Vdc_ref(800V) → [Verr] → [V_PI] → Iref/3 ┬→ [I1err] → [I1_PI] → D1(0.5-PI*0.5) → [Cmp1] → PWM1/N1
              ↑                              │→ [I2err] → [I2_PI] → D2            → [Cmp2] → PWM3/N2
         Vdc_sense                           └→ [I3err] → [I3_PI] → D3            → [Cmp3] → PWM5/N3
                                                                       ↑               ↑
                                                                  Carrier1/2/3    120°交错三角载波
```

- **电压外环**：PI (Kp=0.5, Ki=50)，输出总电流参考，限幅 [0, 125A]
- **电流内环**：三相独立 PI (Kp=0.4, Ki=40)，输出限幅 [-1, 1]，均分电流参考
- **占空比映射**：D_upper = 0.5 − PI_output × 0.5（PI正值→减小上管占空比→增加升压）
- **PWM 生成**：Relational Operator (`duty > carrier`)，三相互差 120° 三角载波 (20kHz)
- **互补 PWM**：Logical Operator NOT 生成下管信号（无死区简化）

### 3. 三相交错载波

| 相位 | 时间向量 | 输出值 | 偏移 |
|------|---------|--------|------|
| Phase A | [0, 25, 50] µs | [0, 1, 0] | 0° |
| Phase B | [0, 16.67, 41.67, 50] µs | [0.667, 0, 1, 0.667] | 120° |
| Phase C | [0, 8.33, 33.33, 50] µs | [0.667, 1, 0, 0.667] | 240° |

### 4. 信号测量

- Vdc_sense：DC-Link 电压（Voltage Measurement，并联在 Cdc_link 两端）
- I1/I2/I3_sense：三相电感电流（Current Measurement，串联在电感与逆变器之间）
- Scope：4 通道显示 Vdc + 三相电流
- Signal Logging：自动记录 Vdc, I1, I2, I3 到 logsout

## 关键参数

| 参数 | 数值 | 说明 |
|------|------|------|
| Vin | 400 V | 充电桩直流输入 |
| Vout | 800 V | 目标电池电压 |
| Pmax | 50 kW | 设计峰值功率 |
| fsw | 20 kHz | PWM 开关频率 |
| L_phase | 0.15 mH | 每相等效绕组电感 |
| L_in | 0.5 mH | 输入滤波电感 |
| C_in | 500 µF | 输入滤波电容 |
| Cdc | 2000 µF | DC-Link 电容 |
| R_batt | 0.05 Ω | 电池内阻 |
| Kp_v, Ki_v | 0.5, 50 | 电压外环 PI |
| Kp_i, Ki_i | 0.4, 40 | 电流内环 PI |

## 已验证结果

| 指标 | 结果 | 状态 |
|------|------|------|
| DC-Link 升压 | 400V → 800.05V | ✅ |
| 稳态纹波 | < 0.02V | ✅ |
| 三相交错 PWM | max\|ΔI\| > 4A | ✅ |
| 仿真稳定性 | 0.02s / 400万数据点 | ✅ |

## 文件清单

| 文件 | 用途 |
|------|------|
| `PMSM_NP_Boost.slx` | Simulink 仿真模型 |
| `build_and_test.m` | 一键重建+测试脚本（含所有参数定义） |
| `rearrange_layout.m` | 布局整理脚本 |
| `PMSM_NP_Boost_Report.md` | 测试报告 |

## 调试中修复的关键问题

1. **载波未交错** → 三相使用各自独立的相位偏移载波（Repeating Sequence, 时间向量以0起始）
2. **占空比映射反向** → D_upper = 0.5 − PI×0.5（PI正值减小D_upper，增加升压比）
3. **电容初始电压0V致涌流** → Cdc 初始电压 400V（等于 Vin）
4. **Compare To Zero 无法接载波** → 改用 Relational Operator（双输入：duty 和 carrier）
5. **电流传感器浮空** → 正确串联在电感 RConn 与逆变器 LConn 之间
6. **过零检测过载** → 关闭比较器 ZeroCross + 全局 Adaptive 模式
7. **Simscape Electrical PMSM 路径不可用** → 改用 SimPowerSystems 三相独立电感

## 待优化项

1. **PMSM 模型**：当前用独立电感，理想情况应使用带中性点的 PMSM 模型（需 Simscape Electrical 零序模型）
2. **电池模型**：当前为理想电压源+内阻，建议替换为 Simscape Battery 模块
3. **死区时间**：当前互补 PWM 无死区，实际应用中需加入
4. **软启动**：当前直接上电，建议加入缓启动控制
5. **SVPWM**：当前为 SPWM（三角载波比较），可升级为 SVPWM
6. **参数整定**：PI 参数为经验值，可根据实际需求优化

## 待讨论

- 是否需要加入电机旋转模式（FOC + 充电模式切换）？
- 电池模型是否需要替换为 Simscape Battery？
- 是否需要加入故障保护逻辑（过流、过压、过温）？
