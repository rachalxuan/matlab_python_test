# 9000 km 星地数传链路完整论证

## 1. 论证目标

本文针对 8.2 GHz 星地数传链路，论证在目标星地斜距 9000 km 条件下：

1. QPSK/OQPSK、20 MBd、卷积码率 \(3/4\) 模式能否满足 3 dB 工程裕量；
2. 地面接收系统最低需要达到多少 \(G/T\)；
3. 接收机在规定 BER 条件下需要达到多少灵敏度；
4. 8PSK、码率 \(2/3\) 模式应采用多大符号速率；
5. 如何利用 100 kBd～100 MBd 的可调符号速率支持不同 MODCOD。

本文统一以**地面接收机 RF 输入端**作为接收功率和灵敏度参考面。

> 本文中的译码门限为初步工程假设，后续需要由完整 MODCOD 仿真或实际设备测试替换。若仿真门限已经包含同步、解调和接收实现损耗，则不能再次增加 1 dB 实现损耗。

---

# 2. 输入参数

## 2.1 公共链路参数

| 参数 | 符号 | 取值 |
|---|---:|---:|
| 工作频率 | \(f\) | 8.2 GHz |
| 目标星地斜距 | \(d_0\) | 9000 km |
| 星上平均射频输出功率 | \(P_t\) | 20 W |
| 星载发射天线增益 | \(G_t\) | 25 dBi |
| 发射端损耗 | \(L_t\) | 1 dB |
| 地面有效接收天线增益 | \(G_r\) | 37 dBi |
| 接收系统噪声温度 | \(T_{\mathrm{sys}}\) | 316 K |
| 大气、极化、指向等传播附加损耗 | \(L_{\mathrm{other}}\) | 2 dB |
| 接收实现损耗 | \(L_{\mathrm{impl}}\) | 1 dB |
| 要求工程链路裕量 | \(M_{\mathrm{req}}\) | 3 dB |
| 协议效率 | \(\eta_p\) | 0.9 |

## 2.2 参数参考面要求

- 20 W 应是扣除功放输出回退后的平均射频输出功率；
- 37 dBi 应是扣除接收馈线、天线罩等接收损耗后的有效增益；
- 316 K 应是接收机 RF 输入参考面上的总系统噪声温度；
- 指向、极化和馈线损耗不能在不同项目中重复扣除；
- 接收灵敏度也必须在同一 RF 输入参考面上定义。

---

# 3. 自由空间传播损耗

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

自由空间传播损耗只由频率和距离决定，与调制方式无关。调制和编码改变的是达到目标 BER/FER 所需的 \(E_b/N_0\) 或 \(E_s/N_0\) 门限。

---

# 4. 发射端 EIRP

20 W 换算为 dBW：

$$
P_t(\mathrm{dBW})
=
10\log_{10}(20)
$$

$$
\boxed{P_t\approx13.01\ \mathrm{dBW}}
$$

EIRP 为：

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

得到：

$$
\boxed{\mathrm{EIRP}=37.01\ \mathrm{dBW}}
$$

---

# 5. 地面接收系统能够提供的 \(G/T\)

接收系统品质因数为：

$$
G/T
=
G_r-10\log_{10}T_{\mathrm{sys}}
$$

代入：

$$
G/T
=
37-10\log_{10}(316)
$$

得到：

$$
\boxed{(G/T)_{\mathrm{actual}}\approx12.00\ \mathrm{dB/K}}
$$

该数值表示在 37 dBi 有效接收增益和 316 K 系统噪声温度假设下，地面接收系统能够实际提供的能力。

---

# 6. 链路能够提供的 \(C/N_0\)

载噪密度比为：

$$
C/N_0
=
\mathrm{EIRP}
+G/T
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

---

# 7. 9000 km 处实际接收功率

接收机 RF 输入端实际载波功率为：

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
\boxed{P_{r,\mathrm{actual}}\approx-87.80\ \mathrm{dBm}}
$$

该数值表示链路在当前参数假设下能够送到接收机 RF 输入端的实际信号功率。能否正常通信，还必须与接收机在相应 MODCOD 下的灵敏度比较。

---

# 8. QPSK/OQPSK 模式完整论证

## 8.1 模式参数

采用：

- 调制方式：QPSK/OQPSK；
- 符号速率：\(R_s=20\) MBd；
- 每符号比特数：\(m=2\)；
- 卷积码率：\(R_c=3/4\)；
- 协议效率：\(\eta_p=0.9\)；
- 目标译码后 BER：暂按 \(10^{-6}\) 级；
- 暂定译码门限：\((E_b/N_0)_{\mathrm{req}}=6\) dB；
- 接收实现损耗：1 dB；
- 要求工程裕量：3 dB。

## 8.2 数据速率

调制后的编码比特率：

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

信道编码器输入信息速率：

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

净载荷业务速率：

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

本文使用 \(R_{\mathrm{info}}\) 计算 \(E_b/N_0\)，因为译码门限以信道编码器输入端的信息比特为参考。协议效率仅用于计算净载荷业务速率，不能作为额外链路增益。

## 8.3 可用 \(E_b/N_0\)

$$
(E_b/N_0)_{\mathrm{avail}}
=
(C/N_0)_{\mathrm{actual}}
-10\log_{10}R_{\mathrm{info}}
$$

代入：

$$
(E_b/N_0)_{\mathrm{avail}}
=
85.80-10\log_{10}(30\times10^6)
$$

$$
\boxed{(E_b/N_0)_{\mathrm{avail}}\approx11.03\ \mathrm{dB}}
$$

考虑译码门限和 1 dB 实现损耗后的总链路裕量为：

$$
M_{\mathrm{total}}
=
11.03-6-1
$$

$$
\boxed{M_{\mathrm{total}}=4.03\ \mathrm{dB}}
$$

要求保留 3 dB 工程裕量，因此满足规定裕量后的额外余量为：

$$
M_{\mathrm{extra}}
=
4.03-3
$$

$$
\boxed{M_{\mathrm{extra}}=1.03\ \mathrm{dB}}
$$

## 8.4 接收机灵敏度的详细推导

### 8.4.1 从 \(E_b/N_0\) 定义出发

信息比特能量为：

$$
E_b=\frac{C}{R_{\mathrm{info}}}
$$

噪声功率谱密度为：

$$
N_0=kT_{\mathrm{sys}}
$$

所以：

$$
\frac{E_b}{N_0}
=
\frac{C}{R_{\mathrm{info}}kT_{\mathrm{sys}}}
$$

当接收功率刚好达到译码门限时：

$$
C_{\min}
=
kT_{\mathrm{sys}}R_{\mathrm{info}}
\left(\frac{E_b}{N_0}\right)_{\mathrm{req}}
$$

考虑接收实现损耗后，dB 形式为：

$$
\boxed{
P_{\mathrm{sens}}(\mathrm{dBW})
=
-228.6
+10\log_{10}T_{\mathrm{sys}}
+10\log_{10}R_{\mathrm{info}}
+(E_b/N_0)_{\mathrm{req}}
+L_{\mathrm{impl}}
}
$$

### 8.4.2 噪声功率谱密度

$$
N_0(\mathrm{dBW/Hz})
=
-228.6+10\log_{10}(316)
$$

$$
\boxed{N_0\approx-203.60\ \mathrm{dBW/Hz}}
$$

### 8.4.3 信息速率项

$$
10\log_{10}(30\times10^6)
\approx74.77\ \mathrm{dB\cdot Hz}
$$

### 8.4.4 代入灵敏度公式

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
P_{\mathrm{sens}}(\mathrm{dBm})
=
-121.83+30
$$

$$
\boxed{P_{\mathrm{sens}}\approx-91.83\ \mathrm{dBm}}
$$

该数值表示接收机刚好达到规定 BER 时所需的 RF 输入功率，不包含 3 dB 工程裕量。

因此对接收机设备提出的要求是：

$$
\boxed{
P_{\mathrm{sens,actual}}
\le
-91.83\ \mathrm{dBm}
}
$$

“灵敏度优于 \(-91.83\) dBm”表示数值应当更负，例如 \(-93\) dBm 优于 \(-91.83\) dBm。

## 8.5 含 3 dB 工程裕量的设计最低接收电平

接收机灵敏度为：

$$
P_{\mathrm{sens}}=-91.83\ \mathrm{dBm}
$$

为了再保留 3 dB 工程裕量，9000 km 处接收功率应满足：

$$
P_{r,\mathrm{design}}
=
P_{\mathrm{sens}}+M_{\mathrm{req}}
$$

$$
P_{r,\mathrm{design}}
=
-91.83+3
$$

$$
\boxed{P_{r,\mathrm{design}}=-88.83\ \mathrm{dBm}}
$$

三项功率之间的关系为：

```text
9000 km 实际接收功率           -87.80 dBm
含 3 dB 裕量的最低设计电平     -88.83 dBm
接收机刚好译码的灵敏度         -91.83 dBm
```

由于 dBm 为负数，数值越接近 0 表示信号越强，因此：

$$
-87.80>-88.83>-91.83
$$

实际接收功率比灵敏度高：

$$
-87.80-(-91.83)
=
4.03\ \mathrm{dB}
$$

即总链路裕量为：

$$
\boxed{M_{\mathrm{total}}=4.03\ \mathrm{dB}}
$$

扣除规定的 3 dB 工程裕量后：

$$
\boxed{M_{\mathrm{extra}}=1.03\ \mathrm{dB}}
$$

## 8.6 反推最低 \(C/N_0\)

达到译码门限所需的最低 \(C/N_0\)，不含工程裕量时为：

$$
(C/N_0)_{\mathrm{demod}}
=
10\log_{10}R_{\mathrm{info}}
+(E_b/N_0)_{\mathrm{req}}
+L_{\mathrm{impl}}
$$

$$
(C/N_0)_{\mathrm{demod}}
=
74.77+6+1
$$

$$
\boxed{(C/N_0)_{\mathrm{demod}}=81.77\ \mathrm{dB\cdot Hz}}
$$

再加入 3 dB 工程裕量：

$$
(C/N_0)_{\mathrm{design}}
=
81.77+3
$$

$$
\boxed{(C/N_0)_{\mathrm{design}}=84.77\ \mathrm{dB\cdot Hz}}
$$

实际链路能够提供：

$$
(C/N_0)_{\mathrm{actual}}=85.80\ \mathrm{dB\cdot Hz}
$$

所以：

$$
85.80-84.77=1.03\ \mathrm{dB}
$$

与接收功率方法得到的额外余量完全一致。

## 8.7 反推最低 \(G/T\)

$$
(G/T)_{\min}
=
(C/N_0)_{\mathrm{design}}
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

当前假设：

$$
(G/T)_{\mathrm{actual}}=12.00\ \mathrm{dB/K}
$$

因此：

$$
12.00-10.97=1.03\ \mathrm{dB}
$$

$$
\boxed{(G/T)_{\mathrm{actual}}>(G/T)_{\min}}
$$

同样说明在规定的 3 dB 工程裕量之外额外保留约 1.03 dB。

如果系统噪声温度固定为 316 K，最低有效接收天线增益为：

$$
G_{r,\min}
=
(G/T)_{\min}+10\log_{10}(316)
$$

$$
\boxed{G_{r,\min}\approx35.97\ \mathrm{dBi}}
$$

如果有效接收天线增益固定为 37 dBi，最大允许系统噪声温度为：

$$
T_{\mathrm{sys,max}}
=
10^{\frac{37-10.97}{10}}
$$

$$
\boxed{T_{\mathrm{sys,max}}\approx401\ \mathrm{K}}
$$

## 8.8 QPSK/OQPSK 最大设计距离

9000 km 处规定裕量之外的额外余量为 1.03 dB。假设其他损耗不随距离变化，最大距离满足：

$$
20\log_{10}\left(\frac{d_{\max}}{9000}\right)
=
1.03
$$

所以：

$$
d_{\max}
=
9000\times10^{1.03/20}
$$

得到：

$$
\boxed{d_{\max}\approx10134\ \mathrm{km}}
$$

因此：

$$
\boxed{d_{\max}>9000\ \mathrm{km}}
$$

## 8.9 QPSK/OQPSK 模式汇总

| 指标 | 最低要求 | 当前假设/计算值 | 结论 |
|---|---:|---:|---|
| 译码门限 | 6 dB | 暂定6 dB | 后续仿真确认 |
| 接收机灵敏度 | 优于 \(-91.83\) dBm | 待设备验证 | 接收机选型要求 |
| 含3 dB裕量的最低接收电平 | \(-88.83\) dBm | \(-87.80\) dBm | 满足，额外1.03 dB |
| 最低 \(C/N_0\) | 84.77 dB·Hz | 85.80 dB·Hz | 满足，额外1.03 dB |
| 最低 \(G/T\) | 10.97 dB/K | 12.00 dB/K | 满足，额外1.03 dB |
| 最低有效接收增益（316 K） | 35.97 dBi | 37 dBi | 满足 |
| 最大系统噪声温度（37 dBi） | 401 K | 316 K | 满足 |
| 最大设计距离 | 不小于9000 km | 约10134 km | 满足 |

---

# 9. 8PSK 模式论证

## 9.1 15 MBd 临界工作点

采用：

- 8PSK：\(m=3\) bit/symbol；
- 符号速率：15 MBd；
- 卷积码率：\(R_c=2/3\)；
- 暂定译码门限：\((E_b/N_0)_{\mathrm{req}}=7\) dB；
- 接收实现损耗：1 dB；
- 工程裕量：3 dB。

信息速率：

$$
R_{\mathrm{info}}
=
15\times3\times\frac23
$$

$$
\boxed{R_{\mathrm{info}}=30\ \mathrm{Mbit/s}}
$$

净载荷速率：

$$
\boxed{R_{\mathrm{payload}}=30\times0.9=27\ \mathrm{Mbit/s}}
$$

接收灵敏度：

$$
P_{\mathrm{sens}}
=
-203.60+74.77+7+1
$$

$$
\boxed{P_{\mathrm{sens}}=-90.83\ \mathrm{dBm}}
$$

含 3 dB 工程裕量的最低设计接收电平：

$$
P_{r,\mathrm{design}}
=
-90.83+3
$$

$$
\boxed{P_{r,\mathrm{design}}=-87.83\ \mathrm{dBm}}
$$

实际接收功率：

$$
P_{r,\mathrm{actual}}=-87.80\ \mathrm{dBm}
$$

因此规定裕量之外仅剩：

$$
\boxed{-87.80-(-87.83)=0.03\ \mathrm{dB}}
$$

最低 \(G/T\) 为：

$$
\boxed{(G/T)_{\min}=11.97\ \mathrm{dB/K}}
$$

当前 \(G/T=12.00\) dB/K，仅高出约 0.03 dB。15 MBd 在数值上满足规定的 3 dB 裕量，但几乎没有取整和参数误差余量，不建议作为稳健设计点。

## 9.2 12 MBd 推荐工作点

将符号速率降低为：

$$
\boxed{R_s=12\ \mathrm{MBd}}
$$

信息速率：

$$
R_{\mathrm{info}}
=
12\times3\times\frac23
$$

$$
\boxed{R_{\mathrm{info}}=24\ \mathrm{Mbit/s}}
$$

净载荷速率：

$$
\boxed{R_{\mathrm{payload}}=24\times0.9=21.6\ \mathrm{Mbit/s}}
$$

接收灵敏度：

$$
P_{\mathrm{sens}}
=
-203.60
+10\log_{10}(24\times10^6)
+7+1
$$

$$
\boxed{P_{\mathrm{sens}}\approx-91.80\ \mathrm{dBm}}
$$

含 3 dB 工程裕量的最低设计接收电平：

$$
\boxed{P_{r,\mathrm{design}}=-88.80\ \mathrm{dBm}}
$$

实际接收功率：

$$
P_{r,\mathrm{actual}}=-87.80\ \mathrm{dBm}
$$

规定裕量之外额外剩余：

$$
\boxed{-87.80-(-88.80)=1.00\ \mathrm{dB}}
$$

最低 \(G/T\) 为：

$$
\boxed{(G/T)_{\min}\approx11.00\ \mathrm{dB/K}}
$$

因此 12 MBd 比 15 MBd 更适合作为当前接收系统参数下的保守设计点。

## 9.3 8PSK 模式比较

| 工作点 | 信息速率 | 净载荷速率 | 灵敏度要求 | 最低 \(G/T\) | 规定裕量外余量 | 结论 |
|---|---:|---:|---:|---:|---:|---|
| 15 MBd、码率2/3 | 30 Mbps | 27 Mbps | \(-90.83\) dBm | 11.97 dB/K | 约0.03 dB | 临界闭合 |
| 12 MBd、码率2/3 | 24 Mbps | 21.6 Mbps | \(-91.80\) dBm | 11.00 dB/K | 约1.00 dB | 推荐初步工作点 |

如果后续完整仿真证明 8PSK 真实译码门限低于 7 dB，则可以重新提高符号速率。

---

# 10. 地面接收端统一要求

如果采用以下推荐模式：

- QPSK/OQPSK：20 MBd、码率 \(3/4\)、门限 6 dB；
- 8PSK：12 MBd、码率 \(2/3\)、门限 7 dB；

则接收端要求为：

| 模式 | 最低 \(G/T\) | 接收机灵敏度要求 |
|---|---:|---:|
| QPSK/OQPSK 20 MBd | 10.97 dB/K | 优于 \(-91.83\) dBm |
| 8PSK 12 MBd | 11.00 dB/K | 优于 \(-91.80\) dBm |

地面接收系统最低闭合条件可以统一规定为：

$$
\boxed{G/T\ge11.0\ \mathrm{dB/K}}
$$

接收机灵敏度要求可以近似统一规定为：

$$
\boxed{P_{\mathrm{sens}}\le-91.8\ \mathrm{dBm}}
$$

项目设计目标建议采用：

$$
\boxed{G/T\ge12.0\ \mathrm{dB/K}}
$$

当前 37 dBi 有效接收增益和 316 K 系统噪声温度对应：

$$
G/T=12.00\ \mathrm{dB/K}
$$

满足建议设计目标。

> 对接收机设备进行验收时，应分别验证它在 QPSK/OQPSK 和 8PSK、对应码率、对应信息速率及规定 BER/FER 下的灵敏度，不能只引用一个与 MODCOD 无关的通用灵敏度数值。

---

# 11. 多 MODCOD 符号速率自适应

对任意 MODCOD：

$$
R_{\mathrm{info}}=R_smR_c
$$

译码门限由信息比特门限表示时：

$$
(C/N_0)_{\mathrm{design}}
=
10\log_{10}(R_smR_c)
+(E_b/N_0)_{\mathrm{req}}
+L_{\mathrm{impl}}
+M_{\mathrm{req}}
$$

最低接收系统品质因数为：

$$
\boxed{
(G/T)_{\min}
=
(C/N_0)_{\mathrm{design}}
-\mathrm{EIRP}
+L_{\mathrm{fs}}
+L_{\mathrm{other}}
-228.6
}
$$

如果使用 \(E_s/N_0\) 门限：

$$
(E_s/N_0)_{\mathrm{req}}
=
(E_b/N_0)_{\mathrm{req}}
+10\log_{10}(mR_c)
$$

则 9000 km 处最大允许符号速率为：

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

因此，100 kBd～100 MBd 的符号速率范围并不表示所有调制都能在 100 MBd 下达到 9000 km，而是表示系统可以针对不同 MODCOD 选择不高于其 \(R_{s,\max}\) 的符号速率。

系统统一接收端要求取所有规定工作模式中的最大值：

$$
\boxed{
(G/T)_{\mathrm{system,req}}
=
\max_i\left\{(G/T)_{\min,i}\right\}
}
$$

如果某个 MODCOD 不满足，可以：

1. 降低符号速率；
2. 采用更强的信道编码；
3. 提高发射功率；
4. 提高发射或接收天线增益；
5. 降低系统噪声温度；
6. 降低传播、指向或极化损耗。

---

# 12. 最终结论

> 在工作频率 8.2 GHz、星地斜距 9000 km、星上平均射频输出功率 20 W、星载发射天线增益 25 dBi、发射端损耗 1 dB、地面有效接收天线增益 37 dBi、接收系统噪声温度 316 K以及传播附加损耗 2 dB 条件下，自由空间传播损耗约为 189.81 dB，发射端 EIRP 为 37.01 dBW，地面接收系统 \(G/T\) 为 12.00 dB/K。由此计算得到链路能够提供的 \(C/N_0\) 为 85.80 dB·Hz，9000 km 处接收机 RF 输入端实际接收功率为 \(-87.80\) dBm。
>
> 对 QPSK/OQPSK、20 MBd、卷积码率 \(3/4\)、暂定译码门限 6 dB 的工作模式，信息速率为 30 Mbps，净载荷速率为 27 Mbps。考虑 1 dB 接收实现损耗后，接收机达到目标误码率所需的灵敏度为 \(-91.83\) dBm；保留 3 dB 工程裕量后，9000 km 处接收功率应不低于 \(-88.83\) dBm。实际接收功率为 \(-87.80\) dBm，因此总链路裕量为 4.03 dB，在保留规定的 3 dB 工程裕量后还剩约 1.03 dB。等价地，该模式要求地面接收系统 \(G/T\ge10.97\) dB/K，当前 \(G/T=12.00\) dB/K，满足要求。对应最大设计通信距离约为 10134 km，大于 9000 km。
>
> 对 8PSK、码率 \(2/3\)、暂定译码门限 7 dB 的模式，15 MBd 时最低 \(G/T\) 约为 11.97 dB/K，在规定 3 dB 裕量之外仅剩约 0.03 dB，属于临界闭合。将符号速率降低至 12 MBd 后，最低 \(G/T\) 降至约 11.00 dB/K，接收机灵敏度要求约为 \(-91.80\) dBm，在规定 3 dB 工程裕量之外还能额外保留约 1 dB，更适合作为初步设计工作点。
>
> 因此，当前推荐将 \(G/T\ge11.0\) dB/K 作为上述 MODCOD 集合的最低闭合条件，将 \(G/T\ge12.0\) dB/K 作为地面接收系统设计目标，并要求接收机在相应 MODCOD、速率和目标 BER/FER 条件下的灵敏度达到约 \(-91.8\) dBm或更优。后续应使用实际设备参数及完整 MODCOD 仿真得到的真实译码门限更新最终链路预算。

---

# 13. 后续验证要求

1. 明确最终可靠性指标为译码后 BER、FER 还是 CER；
2. 用完整 MODCOD 仿真获得真实 \(E_b/N_0\) 或 \(E_s/N_0\) 门限；
3. 确认仿真门限是否已经包含同步和接收实现损耗；
4. 获取地面站在 8.2 GHz 和最低仰角条件下的保证 \(G/T\)；
5. 获取接收机在对应调制、码率、速率和目标错误率下的实测灵敏度；
6. 检查 37 dBi 是否已扣除接收馈线、天线罩和指向损失；
7. 检查 316 K 是否为同一参考面上的总系统噪声温度；
8. 对最坏距离、最低仰角、最大系统噪声温度和最小天线增益组合进行复核；
9. 验证轨道高度和星地可视几何是否允许出现 9000 km 斜距。

## 参考资料

- [CCSDS 130.1-G-3：TM Synchronization and Channel Coding—Summary of Concept and Rationale](https://ccsds.org/Pubs/130x1g3e1.pdf)
- [CCSDS 130.11-G-2：SCCC—Summary of Definition and Performance](https://ccsds.org/Pubs/130x11g2.pdf)
- [ECSS-E-ST-50-01C：Space Data Links—Telemetry Synchronization and Channel Coding](https://ecss.nl/wp-content/uploads/standards/ecss-e/ECSS-E-ST-50-01C31July2008.pdf)
