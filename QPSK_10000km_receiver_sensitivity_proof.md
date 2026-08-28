# QPSK/OQPSK 10,000 km 星地链路接收灵敏度论证

## 1. 论证思路

本文按照以下顺序完成链路闭合判断：

1. 根据 QPSK/OQPSK 的信息速率、译码门限和接收实现损耗，计算接收机达到目标误码率所需的最低 \(C/N_0\)；
2. 根据接收系统噪声温度，将最低 \(C/N_0\) 换算为接收机 RF 输入端灵敏度；
3. 在接收机灵敏度基础上增加 3 dB 工程裕量，得到 10,000 km 处要求的最低接收功率；
4. 根据发射端 EIRP、自由空间传播损耗、传播附加损耗和接收天线增益，计算 10,000 km 处实际接收功率；
5. 将实际接收功率与含 3 dB 工程裕量的最低接收功率比较：

$$
\boxed{
P_{r,\mathrm{actual}}(d)
\ge
P_{\mathrm{sens}}+M_{\mathrm{req}}
}
$$

如果上式成立，则说明该 MODCOD 在目标距离处能够达到规定误码率，并满足 3 dB 工程裕量要求。

本文统一以**地面接收机 RF 输入端**作为接收功率和灵敏度参考面。

---

## 2. 输入参数

### 2.1 链路参数

| 参数 | 符号 | 取值 |
|---|---:|---:|
| 工作频率 | \(f\) | 8.2 GHz |
| 目标星地斜距 | \(d\) | 10,000 km |
| 星上平均射频输出功率 | \(P_t\) | 20 W |
| 星载发射天线增益 | \(G_t\) | 25 dBi |
| 发射端损耗 | \(L_t\) | 1 dB |
| 地面有效接收天线增益 | \(G_r\) | 37 dBi |
| 接收系统噪声温度 | \(T_{\mathrm{sys}}\) | 316 K |
| 大气、极化、指向等传播附加损耗 | \(L_{\mathrm{other}}\) | 2 dB |
| 接收实现损耗 | \(L_{\mathrm{impl}}\) | 1 dB |
| 要求工程链路裕量 | \(M_{\mathrm{req}}\) | 3 dB |

### 2.2 QPSK/OQPSK 模式参数

| 参数 | 符号 | 取值 |
|---|---:|---:|
| 调制方式 |  | QPSK/OQPSK |
| 符号速率 | \(R_s\) | 20 MBd |
| 每符号比特数 | \(m\) | 2 bit/symbol |
| 卷积码率 | \(R_c\) | \(3/4\) |
| 协议效率 | \(\eta_p\) | 0.9 |
| 暂定译码门限 | \((E_b/N_0)_{\mathrm{req}}\) | 6 dB |
| 目标错误率 |  | 译码后 \(BER\le10^{-6}\) 级 |

> 6 dB 为当前初步工程门限，后续应使用完整 MODCOD 仿真或实际接收机测试得到的门限替换。如果仿真门限已经包含同步、解调和接收实现损耗，则不能再增加 1 dB 实现损耗。

---

## 3. QPSK/OQPSK 信息速率

QPSK/OQPSK 每个符号携带：

$$
m=\log_2 4=2\ \mathrm{bit/symbol}
$$

调制器输出的编码比特率为：

$$
R_{\mathrm{air}}
=
R_sm
$$

$$
R_{\mathrm{air}}
=
20\times2
$$

$$
\boxed{R_{\mathrm{air}}=40\ \mathrm{Mbit/s}}
$$

信道编码器输入信息速率为：

$$
R_{\mathrm{info}}
=
R_smR_c
$$

$$
R_{\mathrm{info}}
=
20\times2\times\frac34
$$

$$
\boxed{R_{\mathrm{info}}=30\ \mathrm{Mbit/s}}
$$

按 0.9 协议效率计算，净载荷速率为：

$$
R_{\mathrm{payload}}
=
R_{\mathrm{info}}\eta_p
$$

$$
R_{\mathrm{payload}}
=
30\times0.9
$$

$$
\boxed{R_{\mathrm{payload}}=27\ \mathrm{Mbit/s}}
$$

本文使用 \(R_{\mathrm{info}}\) 计算 \(E_b/N_0\)，因为译码门限以信道编码器输入端的信息比特为参考。协议效率仅用于计算净载荷速率，不能作为额外链路增益。

---

## 4. 接收机达到目标误码率所需的最低 \(C/N_0\)

\(E_b/N_0\) 与 \(C/N_0\) 的关系为：

$$
C/N_0
=
E_b/N_0
+10\log_{10}R_{\mathrm{info}}
$$

考虑接收实现损耗后，接收机刚好达到目标误码率所需的最低载噪密度比为：

$$
(C/N_0)_{\mathrm{demod}}
=
10\log_{10}R_{\mathrm{info}}
+(E_b/N_0)_{\mathrm{req}}
+L_{\mathrm{impl}}
$$

首先计算信息速率项：

$$
10\log_{10}(30\times10^6)
\approx74.77\ \mathrm{dB\cdot Hz}
$$

代入译码门限 6 dB 和实现损耗 1 dB：

$$
(C/N_0)_{\mathrm{demod}}
=
74.77+6+1
$$

得到：

$$
\boxed{
(C/N_0)_{\mathrm{demod}}
=
81.77\ \mathrm{dB\cdot Hz}
}
$$

该数值表示接收机刚好达到规定误码率所需的最低 \(C/N_0\)，尚未加入 3 dB 工程裕量。

加入 3 dB 工程裕量后，链路设计要求为：

$$
(C/N_0)_{\mathrm{design}}
=
(C/N_0)_{\mathrm{demod}}
+M_{\mathrm{req}}
$$

$$
(C/N_0)_{\mathrm{design}}
=
81.77+3
$$

$$
\boxed{
(C/N_0)_{\mathrm{design}}
=
84.77\ \mathrm{dB\cdot Hz}
}
$$

---

## 5. 接收机灵敏度计算

### 5.1 系统噪声功率谱密度

噪声功率谱密度为：

$$
N_0=kT_{\mathrm{sys}}
$$

玻尔兹曼常数采用 dB 形式：

$$
10\log_{10}k
=
-228.6\ \mathrm{dBW/K/Hz}
$$

因此：

$$
N_0(\mathrm{dBW/Hz})
=
-228.6+10\log_{10}T_{\mathrm{sys}}
$$

代入 \(T_{\mathrm{sys}}=316\) K：

$$
N_0
=
-228.6+10\log_{10}(316)
$$

$$
\boxed{N_0\approx-203.60\ \mathrm{dBW/Hz}}
$$

### 5.2 灵敏度

接收机刚好达到目标误码率所需的输入功率为：

$$
P_{\mathrm{sens}}
=
N_0+(C/N_0)_{\mathrm{demod}}
$$

代入：

$$
P_{\mathrm{sens}}
=
-203.60+81.77
$$

$$
P_{\mathrm{sens}}
=
-121.83\ \mathrm{dBW}
$$

dBW 换算为 dBm 时加 30：

$$
P_{\mathrm{sens}}(\mathrm{dBm})
=
-121.83+30
$$

得到：

$$
\boxed{P_{\mathrm{sens}}\approx-91.83\ \mathrm{dBm}}
$$

这表示在 QPSK/OQPSK、20 MBd、码率 \(3/4\)、暂定门限 6 dB条件下，接收机 RF 输入功率达到约 \(-91.83\) dBm 时，接收机刚好能够达到目标误码率。

因此，对接收机提出的设备要求是：

$$
\boxed{
P_{\mathrm{sens,actual}}
\le
-91.83\ \mathrm{dBm}
}
$$

“灵敏度优于 \(-91.83\) dBm”表示数值应更负，例如 \(-93\) dBm优于 \(-91.83\) dBm。

---

## 6. 含 3 dB 裕量的最低设计接收功率

接收机灵敏度为：

$$
P_{\mathrm{sens}}=-91.83\ \mathrm{dBm}
$$

为保证 3 dB 工程裕量，目标距离处接收功率必须满足：

$$
P_{r,\mathrm{actual}}(d)
\ge
P_{\mathrm{sens}}+M_{\mathrm{req}}
$$

因此最低设计接收功率为：

$$
P_{r,\mathrm{design}}
=
-91.83+3
$$

$$
\boxed{
P_{r,\mathrm{design}}
=
-88.83\ \mathrm{dBm}
}
$$

该数值不是接收机灵敏度，而是为了在达到目标误码率的基础上再保留 3 dB 裕量，10,000 km 处实际接收功率必须达到的最低设计电平。

---

## 7. 10,000 km 自由空间传播损耗

$$
L_{\mathrm{fs}}
=
92.45
+20\log_{10}f_{\mathrm{GHz}}
+20\log_{10}d_{\mathrm{km}}
$$

代入 8.2 GHz 和 10,000 km：

$$
L_{\mathrm{fs}}
=
92.45
+20\log_{10}(8.2)
+20\log_{10}(10000)
$$

得到：

$$
\boxed{L_{\mathrm{fs}}\approx190.73\ \mathrm{dB}}
$$

---

## 8. 发射端 EIRP

20 W 换算为 dBW：

$$
P_t
=
10\log_{10}(20)
$$

$$
\boxed{P_t\approx13.01\ \mathrm{dBW}}
$$

发射端 EIRP：

$$
\mathrm{EIRP}
=
P_t+G_t-L_t
$$

$$
\mathrm{EIRP}
=
13.01+25-1
$$

$$
\boxed{\mathrm{EIRP}=37.01\ \mathrm{dBW}}
$$

---

## 9. 10,000 km 处实际接收功率

接收机 RF 输入端实际接收功率为：

$$
P_{r,\mathrm{actual}}
=
\mathrm{EIRP}
-L_{\mathrm{fs}}
-L_{\mathrm{other}}
+G_r
$$

代入：

$$
P_{r,\mathrm{actual}}
=
37.01-190.73-2+37
$$

得到：

$$
P_{r,\mathrm{actual}}
\approx
-118.72\ \mathrm{dBW}
$$

换算为 dBm：

$$
\boxed{
P_{r,\mathrm{actual}}(10000\ \mathrm{km})
\approx
-88.72\ \mathrm{dBm}
}
$$

---

## 10. 链路闭合比较

含 3 dB 工程裕量的最低设计接收功率为：

$$
P_{r,\mathrm{design}}=-88.83\ \mathrm{dBm}
$$

10,000 km 处实际接收功率为：

$$
P_{r,\mathrm{actual}}=-88.72\ \mathrm{dBm}
$$

由于 dBm 为负数，数值越接近 0 表示功率越强。因此：

$$
-88.72>-88.83
$$

满足链路闭合条件：

$$
\boxed{
P_{r,\mathrm{actual}}
\ge
P_{\mathrm{sens}}+3\ \mathrm{dB}
}
$$

实际接收功率超过设计最低电平：

$$
M_{\mathrm{extra}}
=
-88.72-(-88.83)
$$

$$
\boxed{M_{\mathrm{extra}}\approx0.12\ \mathrm{dB}}
$$

这表示在达到目标误码率并保留规定 3 dB 工程裕量之后，还剩约 0.12 dB 额外余量。

---

## 11. 用 \(C/N_0\) 进行等价验证

地面接收系统能够提供的品质因数：

$$
G/T
=
37-10\log_{10}(316)
$$

$$
\boxed{G/T\approx12.00\ \mathrm{dB/K}}
$$

10,000 km 处实际 \(C/N_0\)：

$$
(C/N_0)_{\mathrm{actual}}
=
\mathrm{EIRP}
+G/T
-L_{\mathrm{fs}}
-L_{\mathrm{other}}
+228.6
$$

$$
(C/N_0)_{\mathrm{actual}}
=
37.01+12.00-190.73-2+228.6
$$

$$
\boxed{
(C/N_0)_{\mathrm{actual}}
\approx84.89\ \mathrm{dB\cdot Hz}
}
$$

设计要求为：

$$
(C/N_0)_{\mathrm{design}}=84.77\ \mathrm{dB\cdot Hz}
$$

比较：

$$
84.89-84.77=0.12\ \mathrm{dB}
$$

与接收功率比较得到的结果完全一致。

---

## 12. 最大设计通信距离

10,000 km 处规定裕量之外还有约 0.12 dB额外余量。假设其他损耗保持不变，最大设计距离为：

$$
d_{\max}
=
10000\times10^{0.12/20}
$$

得到：

$$
\boxed{d_{\max}\approx10134\ \mathrm{km}}
$$

因此：

$$
\boxed{d_{\max}>10000\ \mathrm{km}}
$$

---

## 13. 结果汇总

| 指标 | 计算结果 |
|---|---:|
| QPSK/OQPSK信息速率 | 30 Mbps |
| 净载荷业务速率 | 27 Mbps |
| 暂定译码门限 | 6 dB |
| 接收实现损耗 | 1 dB |
| 接收机最低 \(C/N_0\) | 81.77 dB·Hz |
| 接收机灵敏度要求 | 优于 \(-91.83\) dBm |
| 含3 dB裕量的设计 \(C/N_0\) | 84.77 dB·Hz |
| 含3 dB裕量的最低设计接收功率 | \(-88.83\) dBm |
| 10,000 km自由空间传播损耗 | 190.73 dB |
| 发射端EIRP | 37.01 dBW |
| 10,000 km实际接收功率 | \(-88.72\) dBm |
| 10,000 km实际 \(C/N_0\) | 84.89 dB·Hz |
| 保留3 dB后额外余量 | 约0.12 dB |
| 最大设计通信距离 | 约10,134 km |

---

## 14. 最终结论

> 对于 QPSK/OQPSK、20 MBd、卷积码率 \(3/4\) 的工作模式，信息速率为 30 Mbps，按 0.9 协议效率计算的净载荷速率为 27 Mbps。暂取译码门限 \(E_b/N_0=6\) dB，并考虑 1 dB 接收实现损耗，接收机达到目标误码率所需的最低 \(C/N_0\) 为 81.77 dB·Hz，对应接收机 RF 输入端灵敏度要求为优于 \(-91.83\) dBm。为保证 3 dB 工程裕量，10,000 km 处实际接收功率应不低于 \(-88.83\) dBm。
>
> 在 8.2 GHz 工作频率、20 W 平均射频输出功率、25 dBi 星载发射天线增益、1 dB 发射损耗、37 dBi 地面有效接收天线增益、316 K 接收系统噪声温度和 2 dB 传播附加损耗条件下，10,000 km 自由空间传播损耗约为 190.73 dB，计算得到接收机 RF 输入端实际接收功率约为 \(-88.72\) dBm。由于 \(-88.72\) dBm高于含 3 dB 工程裕量的最低设计电平 \(-88.83\) dBm约0.12 dB，因此该链路在当前参数和门限假设下能够满足 10,000 km通信距离和 3 dB工程裕量要求。对应最大设计通信距离约为 10,134 km。

---

## 15. 使用限制与后续验证

1. 当前门限 6 dB 是初步工程假设，必须由完整 MODCOD 仿真或实际接收机测试确认；
2. 如果仿真门限已经包含接收实现损耗，应删除额外的 1 dB实现损耗；
3. 10,000 km处规定裕量之外只有约0.12 dB，虽然数学上满足，但对参数取整、天气、最低仰角和设备偏差非常敏感；
4. 37 dBi必须是同一参考面上的有效接收增益，接收馈线等损耗若未包含必须重新扣除；
5. 316 K必须是同一参考面上的总系统噪声温度；
6. 实际接收机应通过设备手册或测试证明，在 QPSK/OQPSK、20 MBd、码率 \(3/4\) 和目标 BER 条件下灵敏度优于 \(-91.83\) dBm；
7. 正式设计建议继续增加链路能力或适当降低符号速率，使规定裕量之外再保留至少0.5～1 dB；
8. 实际任务还必须验证轨道高度、最低仰角和星地可视几何确实允许10,000 km斜距通信。
