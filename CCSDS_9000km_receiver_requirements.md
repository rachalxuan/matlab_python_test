# 9000 km 星地数传链路及接收端能力要求论证

## 1. 论证目的

本文针对工作频率 8.2 GHz、目标星地斜距 9000 km 的数传链路，完成以下论证：

1. 根据发射功率、天线增益、传播损耗和系统噪声温度计算链路可提供的载噪密度比；
2. 根据调制方式、信道编码、信息速率、译码门限和工程裕量，反推接收端最低 \(C/N_0\)；
3. 将最低 \(C/N_0\) 转换为地面接收系统最低 \(G/T\) 要求；
4. 将译码门限转换为接收机 RF 输入端灵敏度要求；
5. 用假设的 37 dBi 接收天线增益和 316 K 系统噪声温度验证接收端能力；
6. 分别对 QPSK/OQPSK 和 8PSK 工作模式进行链路闭合判断；
7. 给出可用于后续多 MODCOD 速率自适应计算的通用公式。

本文统一以**地面接收机 RF 输入端**作为接收功率和灵敏度参考面。

> \(G/T\) 和接收机灵敏度是接收端能力的两种等价表达。系统级链路论证建议以 \(G/T\) 为主要约束，接收机灵敏度用于设备级交叉验证，二者不能作为两项独立增益重复计入链路预算。

---

## 2. 输入参数与假设

### 2.1 公共链路参数

| 参数 | 符号 | 假设值 |
|---|---:|---:|
| 工作频率 | \(f\) | 8.2 GHz |
| 目标星地斜距 | \(d_0\) | 9000 km |
| 星上平均射频输出功率 | \(P_t\) | 20 W |
| 星载发射天线增益 | \(G_t\) | 25 dBi |
| 发射端损耗 | \(L_t\) | 1 dB |
| 地面有效接收天线增益 | \(G_r\) | 37 dBi |
| 接收系统噪声温度 | \(T_{\mathrm{sys}}\) | 316 K |
| 大气、极化、指向等附加损耗 | \(L_{\mathrm{other}}\) | 2 dB |
| 接收实现损耗 | \(L_{\mathrm{impl}}\) | 1 dB |
| 要求的工程链路裕量 | \(M_{\mathrm{req}}\) | 3 dB |
| 协议效率 | \(\eta_p\) | 0.9 |

### 2.2 参数参考面说明

- 20 W 应为发射端扣除功放输出回退后的平均射频输出功率；如果 20 W 是饱和输出功率，应另外扣除调制对应的输出回退；
- 37 dBi 应为接收参考面上的有效天线增益；如果接收馈线、天线罩或其他损耗尚未包含，应从 37 dBi 中扣除；
- 316 K 应为同一参考面上的总系统噪声温度，包括天线噪声、馈线影响、低噪声放大器和后续接收链噪声；
- 如果 2 dB 附加损耗已经包含指向或极化损耗，就不能再从接收天线增益中重复扣除。

---

## 3. 自由空间传播损耗

频率以 GHz、距离以 km 表示时：

$$
L_{\mathrm{fs}}
=
92.45
+20\log_{10}f_{\mathrm{GHz}}
+20\log_{10}d_{\mathrm{km}}
$$

代入 8.2 GHz 和 9000 km：

$$
L_{\mathrm{fs}}
=
92.45
+20\log_{10}(8.2)
+20\log_{10}(9000)
$$

得到：

$$
\boxed{L_{\mathrm{fs}}\approx189.81\ \mathrm{dB}}
$$

调制方式不会改变自由空间传播损耗。不同调制和信道编码影响的是接收端达到目标 BER/FER 所需的 \(E_b/N_0\) 或 \(E_s/N_0\) 门限。

---

## 4. 发射端 EIRP

20 W 换算为 dBW：

$$
P_t(\mathrm{dBW})
=
10\log_{10}(20)
$$

$$
\boxed{P_t\approx13.01\ \mathrm{dBW}}
$$

等效全向辐射功率为：

$$
\mathrm{EIRP}
=
P_t+G_t-L_t
$$

代入：

$$
\mathrm{EIRP}
=
13.01+25-1
$$

得到：

$$
\boxed{\mathrm{EIRP}=37.01\ \mathrm{dBW}}
$$

---

## 5. 假设接收系统能够提供的 \(G/T\)

接收系统品质因数为：

$$
\frac GT
=
G_r-10\log_{10}T_{\mathrm{sys}}
$$

代入 37 dBi 和 316 K：

$$
\frac GT
=
37-10\log_{10}(316)
$$

得到：

$$
\boxed{(G/T)_{\mathrm{actual}}\approx12.00\ \mathrm{dB/K}}
$$

该数值表示在本文天线增益和系统噪声温度假设下，地面接收系统能够提供的实际接收能力。后文还需要根据 MODCOD 反推最低 \(G/T\)，再进行比较。

---

## 6. 链路可提供的 \(C/N_0\)

星地链路载噪密度比为：

$$
\frac C{N_0}
=
\mathrm{EIRP}
+\frac GT
-L_{\mathrm{fs}}
-L_{\mathrm{other}}
+228.6
$$

代入：

$$
C/N_0
=
37.01+12.00-189.81-2+228.6
$$

得到：

$$
\boxed{(C/N_0)_{\mathrm{actual}}\approx85.80\ \mathrm{dB\cdot Hz}}
$$

该数值是当前发射端、传播路径和接收端假设共同能够提供的载噪密度比。

---

## 7. 9000 km 处的实际接收功率

接收机 RF 输入端的载波功率为：

$$
P_r
=
\mathrm{EIRP}
-L_{\mathrm{fs}}
-L_{\mathrm{other}}
+G_r
$$

代入：

$$
P_r
=
37.01-189.81-2+37
$$

得到：

$$
P_r=-117.80\ \mathrm{dBW}
$$

换算为 dBm：

$$
\boxed{P_r\approx-87.80\ \mathrm{dBm}}
$$

该接收功率还不能单独证明链路闭合，必须与规定 MODCOD 和目标错误率下的接收灵敏度比较。

---

# 8. QPSK/OQPSK 模式接收端要求

## 8.1 QPSK/OQPSK 模式参数

采用：

- 符号速率：\(R_s=20\) MBd；
- QPSK/OQPSK：\(m=\log_2 4=2\) bit/symbol；
- 卷积码率：\(R_c=3/4\)；
- 协议效率：\(\eta_p=0.9\)；
- 暂定译码门限：\((E_b/N_0)_{\mathrm{req}}=6\) dB；
- 接收实现损耗：1 dB；
- 工程链路裕量要求：3 dB。

## 8.2 传输速率

调制器编码比特率为：

$$
R_{\mathrm{air}}
=
R_sm
$$

$$
R_{\mathrm{air}}
=
20\times2
=
40\ \mathrm{Mbit/s}
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
=
30\ \mathrm{Mbit/s}
$$

净载荷业务速率为：

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

本文采用 \(R_{\mathrm{info}}\) 计算 \(E_b/N_0\)，因为译码门限以信道编码器输入端的信息比特为参考。协议效率仅用于计算净载荷速率，不能作为额外链路增益。

## 8.3 反推最低 \(C/N_0\)

达到译码门限并保留规定工程裕量时，最低载噪密度比为：

$$
(C/N_0)_{\mathrm{req}}
=
10\log_{10}R_{\mathrm{info}}
+(E_b/N_0)_{\mathrm{req}}
+L_{\mathrm{impl}}
+M_{\mathrm{req}}
$$

代入：

$$
(C/N_0)_{\mathrm{req}}
=
10\log_{10}(30\times10^6)
+6+1+3
$$

由于：

$$
10\log_{10}(30\times10^6)
\approx74.77\ \mathrm{dB\cdot Hz}
$$

所以：

$$
\boxed{(C/N_0)_{\mathrm{req}}=84.77\ \mathrm{dB\cdot Hz}}
$$

## 8.4 反推地面接收系统最低 \(G/T\)

由链路公式：

$$
C/N_0
=
\mathrm{EIRP}
+G/T
-L_{\mathrm{fs}}
-L_{\mathrm{other}}
+228.6
$$

反推：

$$
(G/T)_{\min}
=
(C/N_0)_{\mathrm{req}}
-\mathrm{EIRP}
+L_{\mathrm{fs}}
+L_{\mathrm{other}}
-228.6
$$

代入：

$$
(G/T)_{\min}
=
84.77-37.01+189.81+2-228.6
$$

得到：

$$
\boxed{(G/T)_{\min}=10.97\ \mathrm{dB/K}}
$$

因此 QPSK/OQPSK 模式要求地面接收系统至少满足：

$$
\boxed{G/T\ge10.97\ \mathrm{dB/K}}
$$

工程指标可取整规定为：

$$
\boxed{G/T\ge11.0\ \mathrm{dB/K}}
$$

当前假设能够提供：

$$
(G/T)_{\mathrm{actual}}=12.00\ \mathrm{dB/K}
$$

比较：

$$
(G/T)_{\mathrm{actual}}-(G/T)_{\min}
=
12.00-10.97
$$

$$
\boxed{\Delta(G/T)=1.03\ \mathrm{dB}}
$$

由于最低 \(G/T\) 的计算中已经包含 3 dB 工程裕量，这 1.03 dB 是满足规定工程裕量后的额外余量。

## 8.5 将最低 \(G/T\) 转换为天线和噪声温度约束

如果系统噪声温度固定为 316 K，则最低有效接收天线增益为：

$$
G_{r,\min}
=
(G/T)_{\min}
+10\log_{10}T_{\mathrm{sys}}
$$

$$
G_{r,\min}
=
10.97+10\log_{10}(316)
$$

得到：

$$
\boxed{G_{r,\min}\approx35.97\ \mathrm{dBi}}
$$

当前 37 dBi 有效接收增益满足要求。

如果有效接收天线增益固定为 37 dBi，则允许的最大系统噪声温度为：

$$
T_{\mathrm{sys,max}}
=
10^{\frac{G_r-(G/T)_{\min}}{10}}
$$

$$
T_{\mathrm{sys,max}}
=
10^{\frac{37-10.97}{10}}
$$

得到：

$$
\boxed{T_{\mathrm{sys,max}}\approx401\ \mathrm{K}}
$$

当前 316 K 系统噪声温度满足要求。

## 8.6 反推接收机灵敏度

接收系统噪声功率谱密度为：

$$
N_0=kT_{\mathrm{sys}}
$$

采用 dB 形式：

$$
N_0(\mathrm{dBW/Hz})
=
-228.6+10\log_{10}T_{\mathrm{sys}}
$$

代入 316 K：

$$
N_0
=
-228.6+10\log_{10}(316)
$$

得到：

$$
\boxed{N_0\approx-203.60\ \mathrm{dBW/Hz}}
$$

不包含工程裕量时，达到目标 BER 所需的接收灵敏度为：

$$
P_{\mathrm{sens}}
=
N_0
+10\log_{10}R_{\mathrm{info}}
+(E_b/N_0)_{\mathrm{req}}
+L_{\mathrm{impl}}
$$

代入：

$$
P_{\mathrm{sens}}
=
-203.60+74.77+6+1
$$

$$
P_{\mathrm{sens}}
=
-121.83\ \mathrm{dBW}
$$

换算为 dBm：

$$
\boxed{P_{\mathrm{sens}}\approx-91.83\ \mathrm{dBm}}
$$

因此，接收机设备应满足：

$$
\boxed{
P_{\mathrm{sens,actual}}
\le
-91.83\ \mathrm{dBm}
}
$$

这里“灵敏度优于 \(-91.83\) dBm”表示数值应该更负，例如 \(-93\) dBm 优于 \(-91.83\) dBm。

## 8.7 接收功率与灵敏度比较

为了在达到译码门限的基础上再保留 3 dB 工程裕量，9000 km 处接收功率应满足：

$$
P_r
\ge
P_{\mathrm{sens}}+M_{\mathrm{req}}
$$

$$
P_r
\ge
-91.83+3
$$

得到：

$$
\boxed{P_r\ge-88.83\ \mathrm{dBm}}
$$

链路计算得到：

$$
P_{r,\mathrm{actual}}=-87.80\ \mathrm{dBm}
$$

因此：

$$
-87.80>-88.83
$$

实际接收功率比接收灵敏度高：

$$
-87.80-(-91.83)
=
4.03\ \mathrm{dB}
$$

其中 3 dB 作为规定工程裕量，剩余：

$$
\boxed{4.03-3=1.03\ \mathrm{dB}}
$$

由此说明，链路余量比较对象是 QPSK/OQPSK 模式在目标 BER 下的接收灵敏度门限，而不是一个未定义的功率数值。

## 8.8 QPSK/OQPSK 模式结论

QPSK/OQPSK、20 MBd、码率 \(3/4\)、译码门限 6 dB 条件下：

| 接收端指标 | 最低要求 | 当前假设 | 结论 |
|---|---:|---:|---:|
| \(C/N_0\) | 84.77 dB·Hz | 85.80 dB·Hz | 满足，额外 1.03 dB |
| \(G/T\) | 10.97 dB/K | 12.00 dB/K | 满足，额外 1.03 dB |
| 有效接收增益（316 K） | 35.97 dBi | 37 dBi | 满足 |
| 最大系统噪声温度（37 dBi） | 401 K | 316 K | 满足 |
| 接收机灵敏度 | 应优于 \(-91.83\) dBm | 待设备验证 | 作为设备要求 |
| 含 3 dB 裕量的最低接收功率 | \(-88.83\) dBm | \(-87.80\) dBm | 满足，额外 1.03 dB |

因此，在地面接收系统满足 \(G/T\ge10.97\) dB/K，且接收机在规定模式和目标 BER 下的灵敏度优于 \(-91.83\) dBm 的条件下，QPSK/OQPSK 模式能够满足 9000 km 通信距离和 3 dB 工程裕量要求。

---

# 9. 8PSK 模式接收端要求

## 9.1 15 MBd 工作点

采用：

- 8PSK：\(m=3\) bit/symbol；
- 符号速率：15 MBd；
- 码率：\(R_c=2/3\)；
- 暂定译码门限：\((E_b/N_0)_{\mathrm{req}}=7\) dB；
- 接收实现损耗：1 dB；
- 工程裕量：3 dB。

信息速率为：

$$
R_{\mathrm{info}}
=
15\times3\times\frac23
$$

$$
\boxed{R_{\mathrm{info}}=30\ \mathrm{Mbit/s}}
$$

净载荷速率为：

$$
R_{\mathrm{payload}}
=
30\times0.9
$$

$$
\boxed{R_{\mathrm{payload}}=27\ \mathrm{Mbit/s}}
$$

最低载噪密度比为：

$$
(C/N_0)_{\mathrm{req}}
=
74.77+7+1+3
$$

$$
\boxed{(C/N_0)_{\mathrm{req}}=85.77\ \mathrm{dB\cdot Hz}}
$$

最低地面接收系统品质因数为：

$$
\boxed{(G/T)_{\min}=11.97\ \mathrm{dB/K}}
$$

接收机灵敏度要求为：

$$
\boxed{P_{\mathrm{sens}}\le-90.83\ \mathrm{dBm}}
$$

保留 3 dB 工程裕量后，9000 km 处接收功率应满足：

$$
\boxed{P_r\ge-87.83\ \mathrm{dBm}}
$$

当前假设只能提供：

$$
(G/T)_{\mathrm{actual}}=12.00\ \mathrm{dB/K}
$$

$$
P_{r,\mathrm{actual}}=-87.80\ \mathrm{dBm}
$$

额外余量仅约：

$$
\boxed{12.00-11.97\approx0.03\ \mathrm{dB}}
$$

因此，15 MBd 工作点虽然在数值上满足 3 dB 规定工程裕量，但几乎处于计算边界。考虑参数取整、最低仰角、雨衰、功放输出误差和接收实现差异，不建议直接作为最终设计点。

## 9.2 推荐的 12 MBd 工作点

将 8PSK 符号速率降低至：

$$
\boxed{R_s=12\ \mathrm{MBd}}
$$

信息速率为：

$$
R_{\mathrm{info}}
=
12\times3\times\frac23
$$

$$
\boxed{R_{\mathrm{info}}=24\ \mathrm{Mbit/s}}
$$

净载荷速率为：

$$
R_{\mathrm{payload}}
=
24\times0.9
$$

$$
\boxed{R_{\mathrm{payload}}=21.6\ \mathrm{Mbit/s}}
$$

最低载噪密度比为：

$$
(C/N_0)_{\mathrm{req}}
=
10\log_{10}(24\times10^6)+7+1+3
$$

$$
\boxed{(C/N_0)_{\mathrm{req}}\approx84.80\ \mathrm{dB\cdot Hz}}
$$

最低 \(G/T\) 为：

$$
\boxed{(G/T)_{\min}\approx11.00\ \mathrm{dB/K}}
$$

灵敏度要求为：

$$
\boxed{P_{\mathrm{sens}}\le-91.80\ \mathrm{dBm}}
$$

保留 3 dB 工程裕量后，接收功率应满足：

$$
\boxed{P_r\ge-88.80\ \mathrm{dBm}}
$$

当前实际接收功率为：

$$
P_{r,\mathrm{actual}}=-87.80\ \mathrm{dBm}
$$

因此在满足规定 3 dB 裕量后还能额外保留约：

$$
\boxed{-87.80-(-88.80)=1.00\ \mathrm{dB}}
$$

8PSK 采用 12 MBd 比 15 MBd 更适合作为当前参数假设下的保守设计点。

## 9.3 8PSK 模式结论

| 8PSK工作点 | 信息速率 | 净载荷速率 | 最低 \(G/T\) | 灵敏度要求 | 规定裕量外额外余量 | 建议 |
|---|---:|---:|---:|---:|---:|---|
| 15 MBd，码率2/3 | 30 Mbps | 27 Mbps | 11.97 dB/K | \(-90.83\) dBm | 约0.03 dB | 仅临界闭合 |
| 12 MBd，码率2/3 | 24 Mbps | 21.6 Mbps | 11.00 dB/K | \(-91.80\) dBm | 约1.00 dB | 推荐初步设计点 |

如果后续仿真证明 8PSK 的真实译码门限显著低于 7 dB，例如约 5.5～6 dB，则可以重新评估 15 MBd 甚至更高符号速率。

---

# 10. 地面接收端统一设计要求

在当前建议工作点下：

- QPSK/OQPSK：20 MBd、码率 \(3/4\)、门限 6 dB；
- 8PSK：12 MBd、码率 \(2/3\)、门限 7 dB。

两种模式对接收端的要求为：

| 工作模式 | 最低 \(G/T\) | 接收机灵敏度要求 |
|---|---:|---:|
| QPSK/OQPSK 20 MBd | 10.97 dB/K | 优于 \(-91.83\) dBm |
| 8PSK 12 MBd | 11.00 dB/K | 优于 \(-91.80\) dBm |

可以将地面接收系统最低闭合条件统一规定为：

$$
\boxed{G/T\ge11.0\ \mathrm{dB/K}}
$$

接收机灵敏度统一要求可近似规定为：

$$
\boxed{P_{\mathrm{sens}}\le-91.8\ \mathrm{dBm}}
$$

考虑设备误差和后续参数变化，建议项目设计目标采用：

$$
\boxed{G/T\ge12.0\ \mathrm{dB/K}}
$$

当前 37 dBi 有效接收天线增益和 316 K 系统噪声温度对应：

$$
G/T=12.00\ \mathrm{dB/K}
$$

满足建议的项目设计目标。

> 正式设备选型时，应检查实际接收机在对应调制、码率、数据率和目标 BER/FER 下的灵敏度，而不能只引用一个与模式和速率无关的通用灵敏度数值。

---

# 11. 多 MODCOD 与符号速率自适应的通用论证

对任意调制编码方式，设：

- 调制阶数：\(M\)；
- 每符号调制比特数：\(m=\log_2M\)；
- 信道码率：\(R_c\)；
- 符号速率：\(R_s\)；
- 译码门限：\((E_b/N_0)_{\mathrm{req}}\)。

信息速率为：

$$
R_{\mathrm{info}}=R_smR_c
$$

最低载噪密度比为：

$$
\boxed{
(C/N_0)_{\mathrm{req}}
=
10\log_{10}(R_smR_c)
+(E_b/N_0)_{\mathrm{req}}
+L_{\mathrm{impl}}
+M_{\mathrm{req}}
}
$$

最低接收系统品质因数为：

$$
\boxed{
(G/T)_{\min}
=
(C/N_0)_{\mathrm{req}}
-\mathrm{EIRP}
+L_{\mathrm{fs}}
+L_{\mathrm{other}}
-228.6
}
$$

等价地，也可以使用 \(E_s/N_0\) 表示：

$$
(E_s/N_0)_{\mathrm{req}}
=
(E_b/N_0)_{\mathrm{req}}
+10\log_{10}(mR_c)
$$

则：

$$
\boxed{
(C/N_0)_{\mathrm{req}}
=
10\log_{10}R_s
+(E_s/N_0)_{\mathrm{req}}
+L_{\mathrm{impl}}
+M_{\mathrm{req}}
}
$$

在地面站实际 \(G/T\) 已知时，9000 km 处每个 MODCOD 的最大符号速率为：

$$
\boxed{
R_{s,\max}
=
10^{
\frac{
(C/N_0)_{\mathrm{actual}}
-(E_s/N_0)_{\mathrm{req}}
-L_{\mathrm{impl}}
-M_{\mathrm{req}}
}{10}
}
}
$$

因此，100 kBd～100 MBd 的宽范围符号速率能够为不同 MODCOD 提供速率自适应能力。对于门限较高的高阶调制，可以降低符号速率，使最低 \(G/T\) 和灵敏度要求降低，从而满足 9000 km 和 3 dB 工程裕量要求。

系统统一接收能力要求应取所有规定工作模式中的最大值：

$$
\boxed{
(G/T)_{\mathrm{system,req}}
=
\max_i\left\{(G/T)_{\min,i}\right\}
}
$$

如果某一模式的最低 \(G/T\) 高于地面站实际 \(G/T\)，可以采取以下措施：

1. 降低该模式的符号速率；
2. 采用更强的信道编码；
3. 提高星上发射功率或发射天线增益；
4. 提高地面接收天线增益；
5. 降低接收系统噪声温度；
6. 降低传播、指向或极化损耗。

---

# 12. 最终论证结论

> 在工作频率 8.2 GHz、星地斜距 9000 km、星上平均射频输出功率 20 W、星载发射天线增益 25 dBi、发射端损耗 1 dB、地面有效接收天线增益 37 dBi、接收系统噪声温度 316 K以及传播附加损耗 2 dB 的条件下，自由空间传播损耗约为 189.81 dB，星上 EIRP 为 37.01 dBW，地面接收系统 \(G/T\) 为 12.00 dB/K，链路能够提供的 \(C/N_0\) 约为 85.80 dB·Hz，9000 km 处接收功率约为 \(-87.80\) dBm。
>
> 对 QPSK/OQPSK、20 MBd、卷积码率 \(3/4\)、译码门限 6 dB 的工作模式，在另计 1 dB 接收实现损耗并保留 3 dB 工程裕量后，要求地面接收系统 \(G/T\ge10.97\) dB/K，接收机灵敏度应优于 \(-91.83\) dBm，9000 km 处接收功率应不低于 \(-88.83\) dBm。当前假设的 \(G/T=12.00\) dB/K 和接收功率 \(-87.80\) dBm 均满足要求，并在规定 3 dB 工程裕量之外额外保留约 1.03 dB。因此，该 QPSK/OQPSK 模式能够满足 9000 km 通信距离要求。
>
> 对 8PSK、码率 \(2/3\)、译码门限 7 dB 的工作模式，15 MBd 时最低 \(G/T\) 约为 11.97 dB/K，当前接收系统仅在规定裕量之外保留约 0.03 dB，不宜作为稳健设计点。将符号速率降低至 12 MBd 后，最低 \(G/T\) 降至约 11.00 dB/K，接收灵敏度要求约为 \(-91.80\) dBm，在规定 3 dB 工程裕量之外能够额外保留约 1 dB，适合作为当前阶段的保守设计点。
>
> 因此，本项目可将 \(G/T\ge11.0\) dB/K 作为当前 MODCOD 集合的最低闭合条件，将 \(G/T\ge12.0\) dB/K 作为地面接收系统设计目标，并要求接收机在对应 MODCOD 和数据率下的灵敏度达到约 \(-91.8\) dBm或更优。后续应使用实际天线、馈线、LNA和接收机参数，以及完整 MODCOD 仿真得到的译码门限，对上述接收端要求和链路余量进行最终修正。

---

# 13. 后续验证项目

在方案设计和设备选型阶段，应进一步完成以下验证：

1. 明确目标指标是译码后 BER、FER 还是 CER，并统一门限口径；
2. 通过完整 MODCOD 仿真获得真实 \(E_b/N_0\) 或 \(E_s/N_0\) 门限；
3. 确认仿真门限是否已包含同步、载波恢复和接收实现损耗，避免重复增加 1 dB；
4. 获取实际地面站在 8.2 GHz、最低仰角条件下的实测或保证 \(G/T\)；
5. 获取接收机在各 MODCOD、符号速率和目标 BER/FER 下的灵敏度；
6. 将接收馈线、天线罩、指向误差、极化误差和天气影响统一到同一参考面；
7. 对最坏距离、最低仰角、最高系统噪声温度和最小天线增益组合进行最坏工况复核；
8. 验证轨道高度和星地可视几何确实允许出现 9000 km 斜距通信。
