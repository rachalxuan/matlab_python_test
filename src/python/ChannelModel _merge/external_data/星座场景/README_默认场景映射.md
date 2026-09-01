# 星座场景默认终端与卫星映射说明

本目录用于存放各星座场景的外部轨迹数据。无界面项目使用数字编号选择星座场景，`Utilities/ConstellationSceneLoader.m` 根据编号进入对应 `switch` 分支，选择默认信关站终端、默认过境卫星和轨迹数据。

## 星座场景编号

| 编号 | 星座场景 | 默认信关站/终端 | 默认卫星 |
| --- | --- | --- | --- |
| 1 | Iridium Next场景 | DVB1 | S0301 |
| 2 | Inmarsat场景 | DVB1 | F11 |
| 3 | Globalstar场景 | DVB1 | S45 |
| 4 | Leogeo场景 | DVB1 | S022 |
| 5 | Meteosat场景 | DVB1 | M1-1 |
| 6 | Orbcomm场景 | DVB1 | S028 |

## 说明

- `main.m` 或外部调用方设置 `config.constellationSceneCode` 为上表编号。
- 终端经纬高由 `Utilities/ConstellationSceneLoader.m` 中的默认终端表统一设置。
- 终端移动速度默认为 0，表示静止终端。
- 轨迹刷新率 `dT` 默认为 1 秒。
- 仿真总时长 `Ttotal` 默认取该场景下默认终端与默认卫星的过境时间总时长。
- 后续如需更换某个场景默认使用的终端或卫星，可修改 `Utilities/ConstellationSceneLoader.m` 中对应编号分支。
