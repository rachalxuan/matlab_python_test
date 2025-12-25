import React from "react";
import ReactDOM from "react-dom/client";
import "normalize.css";
import "./index.scss";
import App from "./App";
import { RouterProvider } from "react-router-dom";
import router from "./router";
import { Provider } from "react-redux";
import store from "./store";

// https://github.com/rachalxuan/react-jike-2025.git
const root = ReactDOM.createRoot(document.getElementById("root"));
root.render(
  <Provider store={store}>
    <RouterProvider router={router} />
  </Provider>
);
