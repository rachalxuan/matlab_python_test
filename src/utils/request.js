// src/utils/request.js

// Development uses the separately started local Python server. In a production
// build, API requests stay on the same origin that served the React page, so a
// controller on another LAN device calls the simulation computer rather than
// its own 127.0.0.1.
const BASE_URL =
  process.env.NODE_ENV === "development" ? "http://127.0.0.1:5000" : "";

const request = async (urlOrConfig, options = {}) => {
  let url;
  let config;

  if (typeof urlOrConfig === "string") {
    url = urlOrConfig;
    config = options;
  } else {
    url = urlOrConfig.url;
    config = { ...urlOrConfig };
  }

  if (config.data) {
    config.body = JSON.stringify(config.data);
    delete config.data;
  }

  const fullUrl = `${BASE_URL}${url}`;
  const defaultOptions = {
    method: "GET",
    headers: {
      "Content-Type": "application/json",
    },
    ...config,
  };

  try {
    console.log(`[API] Request: ${fullUrl}`);
    const response = await fetch(fullUrl, defaultOptions);

    if (!response.ok) {
      throw new Error(`HTTP Error: ${response.status}`);
    }

    return await response.json();
  } catch (error) {
    console.error("[API] Request failed:", error);
    throw error;
  }
};

export { request };
