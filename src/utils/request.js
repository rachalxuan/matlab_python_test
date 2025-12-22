import axios from "axios";

import router from "@/router";
//axios的封装处理

// src/utils/request.js

// 1. 定义基础路径 (指向你的 Python 后台)
const BASE_URL = "http://127.0.0.1:5000";

/**
 * 封装后的 fetch 请求工具
 * @param {string} url - 接口地址 (例如 '/simulate')
 * @param {object} options - fetch 配置项
 */
const request = async (url, options = {}) => {
  // 自动拼接完整地址
  const fullUrl = `${BASE_URL}${url}`;

  // 默认配置 (自动带上 JSON 头)
  const defaultOptions = {
    headers: {
      "Content-Type": "application/json",
    },
    ...options, // 允许外部覆盖
  };

  try {
    // 开发环境下打印请求日志，方便调试
    console.log(`📡 [API] 发起请求: ${fullUrl}`);

    const response = await fetch(fullUrl, defaultOptions);

    // 统一处理 HTTP 错误状态码
    if (!response.ok) {
      throw new Error(`HTTP Error: ${response.status}`);
    }

    // 解析 JSON
    return await response.json();
  } catch (error) {
    console.error("❌ [API] 请求失败:", error);
    throw error; // 继续把错误抛出去给页面处理
  }
};

export { request };
