# 星地数传链路 9000 km 通信距离论证

## ——QPSK/OQPSK、目标误码率 \(BER\le10^{-6}\)

## 1. 论证结论

在以下条件下：

- 工作频率：8.2 GHz；
- 星地斜距：9000 km；
- 星上平均射频输出功率：20 W；
- 星载发射天线增益：25 dBi；
- 地面接收天线增益：37 dBi；
- 接收系统噪声温度：316 K；
- 传播附加损耗：2 dB；
- 接收实现损耗：1 dB；
- 要求工程裕量：3 dB；
- 调制方式：QPSK/OQPSK；
- 卷积码率：\(3/4\)；
- 目标误码率：\(BER\le10^{-6}\)；

链路在 9000 km 处允许的最大符号速率为：

$$
\boxed{R_{s,\max}\approx17.54\ \mathrm{MBd}}
$$

选择：

$$
\boxed{R_s=15\ \mathrm{MBd}}
$$

时，9000 km 链路裕量为：

$$
\boxed{M\approx3.68\ \mathrm{dB}}
$$

对应最大设计通信距离为：

$$
\boxed{d_{\max}\approx9733\ \mathrm{km}}
$$

因此：

$$
\boxed{d_{\max}>9000\ \mathrm{km}}
$$

即 QPSK/OQPSK、卷积码率 \(3/4\)、15 MBd 工作点能够满足 9000 km 通信距离、\(BER\le10^{-6}\) 和 3 dB 工程裕量要求。

---

## 2. 链路预算输入参数

| 参数 | 符号 | 取值 |
|---|---:|---:|
| 工作频率 | \(f\) | 8.2 GHz |
| 目标星地斜距 | \(d_0\) | 9000 km |
| 星上发射功率 | \(P_t\) | 20 W |
| 星载发射天线增益 | \(G_t\) | 25 dBi |
| 发射端损耗 | \(L_t\) | 1 dB |
| 地面接收天线增益 | \(G_r\) | 37 dBi |
| 接收系统噪声温度 | \(T_{\mathrm{sys}}\) | 316 K |
| 大气、极化、指向等附加损耗 | \(L_{\mathrm{other}}\) | 2 dB |
| 接收实现损耗 | \(L_{\mathrm{impl}}\) | 1 dB |
| 要求工程链路裕量 | \(M_{\mathrm{req}}\) | 3 dB |
| 调制方式 |  | QPSK/OQPSK |
| 卷积码率 | \(R_c\) | \(3/4\) |
| 目标误码率 |  | \(BER\le10^{-6}\) |
| 协议效率 | \(\eta_p\) | 0.9 |

传播附加损耗和实现损耗采用不同处理：

- 传播附加损耗 \(L_{\mathrm{other}}\) 从 \(C/N_0\) 中扣除；
- 接收实现损耗 \(L_{\mathrm{impl}}\) 加到译码所需门限上；
- 两项损耗不能重复扣除。

20 W 应理解为发射机输出端的平均射频功率。如果 20 W 是功放饱和功率，还需要根据实际功放输出回退重新计算平均 EIRP。

---

## 3. 自由空间传播损耗

频率采用 GHz、距离采用 km 时：

$$
L_{\mathrm{fs}}
=
92.45
+20\log_{10}f_{\mathrm{GHz}}
+20\log_{10}d_{\mathrm{km}}
$$

代入：

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

自由空间损耗由频率和传播距离决定，与具体调制方式无关。

---

## 4. 发射端 EIRP

20 W 换算为 dBW：

$$
P_t(\mathrm{dBW})
=
10\log_{10}(20)
$$

$$
P_t\approx13.01\ \mathrm{dBW}
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

## 5. 接收端 \(G/T\)

地面站品质因数为：

$$
\frac GT
=
G_r-10\log_{10}T_{\mathrm{sys}}
$$

代入：

$$
\frac GT
=
37-10\log_{10}(316)
$$

由于：

$$
10\log_{10}(316)\approx25.00\ \mathrm{dB}
$$

因此：

$$
\boxed{G/T\approx12.00\ \mathrm{dB/K}}
$$

---

## 6. 载噪密度比 \(C/N_0\)

载噪密度比为：

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
\boxed{C/N_0\approx85.80\ \mathrm{dB\cdot Hz}}
$$

该数值由发射功率、天线增益、传播距离、附加损耗和接收系统噪声温度共同决定。

---

## 7. QPSK/OQPSK 译码门限

QPSK 每个信道符号包含：

$$
m=\log_2 4=2\ \mathrm{bit/symbol}
$$

卷积码率为：

$$
R_c=\frac34
$$

因此，每个信道符号承载的有效信息比特数为：

$$
\eta=mR_c
$$

$$
\eta=2\times\frac34=1.5\ \mathrm{bit/symbol}
$$

根据 CCSDS 兼容卷积码的公开性能数据，对 8920 bit 量级帧、AWGN 信道、软判决 Viterbi 译码，在 \(10^{-6}\) 级错误率要求下，暂取：

$$
\boxed{(E_b/N_0)_{\mathrm{req}}=7.60\ \mathrm{dB}}
$$

该数值采用帧错误率 \(FER=10^{-6}\) 的参考性能，因此用于 \(BER\le10^{-6}\) 的初步论证是偏保守的。

对应的符号能量噪声密度比门限为：

$$
(E_s/N_0)_{\mathrm{req}}
=
(E_b/N_0)_{\mathrm{req}}
+10\log_{10}(mR_c)
$$

代入：

$$
(E_s/N_0)_{\mathrm{req}}
=
7.60+10\log_{10}(1.5)
$$

得到：

$$
\boxed{(E_s/N_0)_{\mathrm{req}}\approx9.36\ \mathrm{dB}}
$$

在理想相干 AWGN 条件下，QPSK 与 OQPSK 的功率效率基本相同，因此可以采用相同的 \(E_b/N_0\) 门限。

---

## 8. 根据链路要求反推最大符号速率

信息速率为：

$$
R_{\mathrm{info}}
=
R_s mR_c
$$

可用比特能量噪声密度比为：

$$
(E_b/N_0)_{\mathrm{avail}}
=
C/N_0-10\log_{10}R_{\mathrm{info}}
$$

代入 \(R_{\mathrm{info}}=R_smR_c\)：

$$
(E_b/N_0)_{\mathrm{avail}}
=
C/N_0-10\log_{10}(R_smR_c)
$$

链路裕量定义为：

$$
M
=
(E_b/N_0)_{\mathrm{avail}}
-(E_b/N_0)_{\mathrm{req}}
-L_{\mathrm{impl}}
$$

为了满足 3 dB 工程裕量，必须有：

$$
M\ge M_{\mathrm{req}}
$$

即：

$$
C/N_0
-10\log_{10}(R_smR_c)
-(E_b/N_0)_{\mathrm{req}}
-L_{\mathrm{impl}}
\ge M_{\mathrm{req}}
$$

整理得到：

$$
10\log_{10}(R_smR_c)
\le
C/N_0
-(E_b/N_0)_{\mathrm{req}}
-L_{\mathrm{impl}}
-M_{\mathrm{req}}
$$

因此最大信息速率为：

$$
R_{\mathrm{info,max}}
=
10^{
\frac{
C/N_0
-(E_b/N_0)_{\mathrm{req}}
-L_{\mathrm{impl}}
-M_{\mathrm{req}}
}{10}
}
$$

代入：

$$
R_{\mathrm{info,max}}
=
10^{
\frac{
85.80-7.60-1-3
}{10}
}
$$

得到：

$$
\boxed{R_{\mathrm{info,max}}\approx26.32\ \mathrm{Mbit/s}}
$$

QPSK 卷积码 \(3/4\) 的有效效率为 1.5 bit/symbol，因此：

$$
R_{s,\max}
=
\frac{R_{\mathrm{info,max}}}{1.5}
$$

$$
R_{s,\max}
=
\frac{26.32}{1.5}
$$

得到：

$$
\boxed{R_{s,\max}\approx17.54\ \mathrm{MBd}}
$$

这表示在当前链路参数和门限假设下，只要：

$$
\boxed{R_s\le17.54\ \mathrm{MBd}}
$$

QPSK/OQPSK 卷积码 \(3/4\) 就可以在 9000 km 处满足 3 dB 工程裕量要求。

---

## 9. 选择 15 MBd 工作点

为了避免工作在理论边界上，选取：

$$
\boxed{R_s=15\ \mathrm{MBd}}
$$

### 9.1 传输速率

调制后的编码比特率为：

$$
R_{\mathrm{air}}
=
R_s m
$$

$$
R_{\mathrm{air}}
=
15\times2
=
30\ \mathrm{Mbit/s}
$$

编码前信息速率为：

$$
R_{\mathrm{info}}
=
R_s mR_c
$$

$$
R_{\mathrm{info}}
=
15\times2\times\frac34
=
22.5\ \mathrm{Mbit/s}
$$

考虑 0.9 协议效率后：

$$
R_{\mathrm{payload}}
=
R_{\mathrm{info}}\eta_p
$$

$$
R_{\mathrm{payload}}
=
22.5\times0.9
$$

得到：

$$
\boxed{R_{\mathrm{payload}}=20.25\ \mathrm{Mbit/s}}
$$

### 9.2 可用 \(E_b/N_0\)

$$
(E_b/N_0)_{\mathrm{avail}}
=
85.80-10\log_{10}(22.5\times10^6)
$$

得到：

$$
\boxed{(E_b/N_0)_{\mathrm{avail}}\approx12.28\ \mathrm{dB}}
$$

### 9.3 链路裕量

所需译码门限加实现损耗为：

$$
(E_b/N_0)_{\mathrm{total,req}}
=
7.60+1
=
8.60\ \mathrm{dB}
$$

所以：

$$
M
=
12.28-8.60
$$

得到：

$$
\boxed{M\approx3.68\ \mathrm{dB}}
$$

由于：

$$
3.68>3
$$

因此 9000 km 链路满足规定的 3 dB 工程裕量，并额外保留：

$$
\boxed{3.68-3=0.68\ \mathrm{dB}}
$$

---

## 10. 最大设计通信距离

在其他参数不变、仅自由空间损耗随距离变化时：

$$
L_{\mathrm{fs}}(d_2)-L_{\mathrm{fs}}(d_1)
=
20\log_{10}\frac{d_2}{d_1}
$$

9000 km 处实际裕量为 3.68 dB，要求裕量为 3 dB，因此可以用于增加距离的余量为：

$$
\Delta M
=
3.68-3
=
0.68\ \mathrm{dB}
$$

最大距离满足：

$$
20\log_{10}
\left(
\frac{d_{\max}}{9000}
\right)
=
0.68
$$

所以：

$$
d_{\max}
=
9000\times10^{0.68/20}
$$

得到：

$$
\boxed{d_{\max}\approx9733\ \mathrm{km}}
$$

因此：

$$
\boxed{9733\ \mathrm{km}>9000\ \mathrm{km}}
$$

完成通信距离不小于 9000 km 的链路闭合论证。

---

## 11. 100 kBd～100 MBd 可调符号速率能否支持其他调制

可以，但准确说法是：

> 100 kBd～100 MBd 的宽范围符号速率为不同 MODCOD 提供了速率自适应能力。并不是所有调制都能在 100 MBd 下达到 9000 km，而是可以根据各 MODCOD 的 \(E_s/N_0\) 门限降低符号速率，使链路满足 9000 km 和 3 dB 裕量。

对于任意 MODCOD，其 9000 km 最大允许符号速率为：

$$
\boxed{
R_{s,\max}
=
10^{
\frac{
C/N_0
-(E_s/N_0)_{\mathrm{req}}
-L_{\mathrm{impl}}
-M_{\mathrm{req}}
}{10}
}
}
$$

在本链路中：

$$
\boxed{
R_{s,\max}
=
10^{
\frac{
85.80
-(E_s/N_0)_{\mathrm{req}}
-1-3
}{10}
}
}
$$

只要实际符号速率满足：

$$
100\ \mathrm{kBd}
\le R_s
\le
\min(100\ \mathrm{MBd},R_{s,\max})
$$

该 MODCOD 就能完成 9000 km 链路闭合。

在最低符号速率 100 kBd 时：

$$
(E_s/N_0)_{\mathrm{avail}}
=
85.80-10\log_{10}(100\times10^3)
$$

$$
(E_s/N_0)_{\mathrm{avail}}
=
85.80-50
=
35.80\ \mathrm{dB}
$$

扣除 1 dB 实现损耗和 3 dB 工程裕量后，允许的 MODCOD 门限最高约为：

$$
(E_s/N_0)_{\mathrm{req,max}}
=
35.80-1-3
$$

$$
\boxed{(E_s/N_0)_{\mathrm{req,max}}\approx31.80\ \mathrm{dB}}
$$

一般 BPSK、QPSK、8PSK、16APSK 和 32APSK 完整 MODCOD 的门限远低于 31.8 dB。因此从纯链路预算角度看：

$$
\boxed{\text{100 kBd～100 MBd 的可调范围足以让其他调制通过降速满足 9000 km}}
$$

但代价是符号速率降低后，信息速率和净载荷速率也按比例降低。

作为初步估计：

| MODCOD | 暂定 \(E_s/N_0\) 门限 | 9000 km 最大符号速率 |
|---|---:|---:|
| BPSK，卷积码 1/2 | 3.39 dB | 约 69.4 MBd |
| QPSK/OQPSK，卷积码 3/4 | 9.36 dB | 约 17.5 MBd |
| 8PSK，SCCC ACM10 | 约 8.50 dB | 约 21.4 MBd |
| 16APSK，SCCC ACM14 | 约 10.80 dB | 约 12.6 MBd |
| 32APSK，SCCC ACM18 | 约 13.60 dB | 约 6.6 MBd |

表中 8PSK 允许速率高于 QPSK，是因为两者采用的编码不同：8PSK 使用性能更强的 SCCC，QPSK 使用传统卷积码。不能仅按照调制阶数比较门限。

---

## 12. 最终结论表述

> 在 8.2 GHz 工作频率、9000 km 星地斜距、20 W 平均射频输出功率、25 dBi 星载发射天线增益、37 dBi 地面接收天线增益和 316 K 接收系统噪声温度条件下，考虑 1 dB 发射损耗、2 dB 传播附加损耗后，接收端载噪密度比为 85.80 dB·Hz。针对目标误码率 \(BER\le10^{-6}\)，QPSK/OQPSK 卷积码率 3/4 的参考译码门限取 \(E_b/N_0=7.60\) dB，并另计 1 dB 接收实现损耗和 3 dB 工程裕量。由链路预算反推得到 9000 km 处最大允许符号速率约为 17.54 MBd。选择 15 MBd 作为工作符号速率时，信息速率为 22.5 Mbit/s，按 0.9 协议效率计算的净载荷速率为 20.25 Mbit/s，9000 km 处链路裕量约为 3.68 dB，对应最大设计通信距离约为 9733 km。因此，该工作模式满足通信距离不小于 9000 km 的要求。系统符号速率可在 100 kBd 至 100 MBd 范围内调整，可通过自适应降低符号速率，使 BPSK、QPSK、8PSK 和 APSK 等不同 MODCOD 在 9000 km 处完成链路闭合。

## 13. 使用说明

- 以上结论证明的是 QPSK/OQPSK 在 15 MBd 下满足 9000 km；
- QPSK 在 20 MBd 下欠缺约 0.57 dB，不能按当前保守门限直接判定通过；
- 如果必须同时达到 27 Mbps 净载荷速率，需要增加约 0.57 dB 链路能力，或改用更强的 Turbo、LDPC、SCCC 编码；
- 其他调制的最终符号速率应由各自完整 MODCOD 仿真门限代入通用公式确定；
- 后续仿真要验证 \(BER\le10^{-6}\)，零误码情况下至少应累计约 \(3\times10^6\) 个有效译码信息比特，才能给出约 95% 置信水平的初步上界；
- 9000 km 为无线链路预算距离，实际任务还必须验证轨道高度、最低仰角和星地可视几何。

## 14. 参考资料

- [CCSDS 130.1-G-3：TM Synchronization and Channel Coding—Summary of Concept and Rationale](https://ccsds.org/Pubs/130x1g3e1.pdf)
- [CCSDS 130.11-G-2：SCCC—Summary of Definition and Performance](https://ccsds.org/Pubs/130x11g2.pdf)
- [ECSS-E-ST-50-01C：Space Data Links—Telemetry Synchronization and Channel Coding](https://ecss.nl/wp-content/uploads/standards/ecss-e/ECSS-E-ST-50-01C31July2008.pdf)
