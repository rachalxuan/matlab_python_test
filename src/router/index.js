import Layout from "@/pages/Layout";
import Login from "@/pages/Login";
import { createHashRouter } from "react-router-dom";
import { AuthRoute } from "@/components/AuthRoute";
// import Home from "@/pages/Home";
// import Article from "@/pages/Article";
// import Publish from "@/pages/Publish";
import { lazy, Suspense } from "react";

const Home = lazy(() => import("@/pages/Home"));
const Article = lazy(() => import("@/pages/Article"));
const Publish = lazy(() => import("@/pages/Publish"));
const MatlabFFT = lazy(() => import("@/pages/MatlabFFT"));

const router = createHashRouter([
  {
    path: "/",
    // 当用户访问根路径 / 时，React Router 不会直接渲染 Layout，而是先渲染 AuthRoute
    element: (
      <AuthRoute>
        <Layout />
      </AuthRoute>
    ),
    children: [
      {
        path: "",
        element: (
          <Suspense fallback={"加载中"}>
            <Home />
          </Suspense>
        ),
      },
      {
        path: "article",
        element: (
          <Suspense fallback={"加载中"}>
            <Article />
          </Suspense>
        ),
      },
      {
        path: "publish",
        element: (
          <Suspense fallback={"加载中"}>
            <Publish />
          </Suspense>
        ),
      },
      {
        path: "matlab",
        element: (
          <Suspense fallback={"加载中"}>
            <MatlabFFT />
          </Suspense>
        ),
      },
    ],
  },
  {
    path: "/login",
    element: <Login />,
  },
]);
export default router;
