import { createHashRouter } from "react-router-dom";

// import Home from "@/pages/Home";
// import Article from "@/pages/Article";
// import Publish from "@/pages/Publish";
import { lazy, Suspense } from "react";
import Layout from "@/pages/Layout";

// const Home = lazy(() => import("@/pages/Home"));
// const Article = lazy(() => import("@/pages/Article"));
// const Publish = lazy(() => import("@/pages/Publish"));
const MatlabFFT = lazy(() => import("@/pages/MatlabFFT"));

const router = createHashRouter([
  {
    path: "/",
    // 当用户访问根路径 / 时，React Router 不会直接渲染 Layout，而是先渲染 AuthRoute
    element: <Layout />,
    children: [
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
]);
export default router;
