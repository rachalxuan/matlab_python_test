import numpy as np
from scipy.io import loadmat


FILES = [
    ("std2_TDL", r"E:\matlab_project\v3.0\v3.0\channel\2-ChannelData.mat"),
    ("std3_CDL", r"E:\matlab_project\v3.0\v3.0\channel\3-ChannelData.mat"),
    ("std4_ITU_P681", r"E:\matlab_project\v3.0\v3.0\channel\4-ChannelData.mat"),
    ("std5_Jakes", r"E:\matlab_project\v3.0\v3.0\channel\ChannelData_5.mat"),
    ("std6_CLoo", r"E:\matlab_project\v3.0\v3.0\channel\ChannelData_6.mat"),
    ("std7_Corazza", r"E:\matlab_project\v3.0\v3.0\channel\ChannelData_7.mat"),
    ("std8_Lutz", r"E:\matlab_project\v3.0\v3.0\channel\ChannelData_8.mat"),
]


for name, path in FILES:
    h_matrix = np.asarray(loadmat(path)["H_Martix_tMode"])
    if h_matrix.ndim == 2:
        h_matrix = h_matrix[:, :, None]
    path_power = np.mean(np.abs(h_matrix) ** 2, axis=(1, 2))
    dominant = int(np.argmax(path_power))
    h = h_matrix[dominant].reshape(-1, order="F")
    h = h[np.abs(h) > 0]
    amplitude = np.abs(h)
    amplitude_db = 20 * np.log10(
        np.maximum(amplitude / np.sqrt(np.mean(amplitude**2)), 1e-15)
    )
    phase_step = np.angle(h[1:] * np.conj(h[:-1]))
    reliable = (amplitude[1:] > np.median(amplitude) * 0.1) & (
        amplitude[:-1] > np.median(amplitude) * 0.1
    )
    phase_step_deg = np.abs(np.rad2deg(phase_step[reliable]))
    jump_rate_pct = 100 * np.mean(phase_step_deg > 45)
    print(
        f"{name:15s} shape={str(h_matrix.shape):18s} "
        f"amp_dB p1/med/p99={np.percentile(amplitude_db, 1):7.2f}/"
        f"{np.median(amplitude_db):6.2f}/{np.percentile(amplitude_db, 99):6.2f} "
        f"min={amplitude_db.min():8.2f} "
        f"|dphi| p99/max={np.percentile(phase_step_deg, 99):7.2f}/"
        f"{phase_step_deg.max():7.2f} deg >45deg={jump_rate_pct:6.3f}%"
    )
