import { Layout, Menu, Popconfirm } from "antd";
import {
  HomeOutlined,
  DiffOutlined,
  EditOutlined,
  FundOutlined,
} from "@ant-design/icons";
import "./index.scss";
import { useNavigate, Outlet, useLocation } from "react-router-dom";
import { useEffect } from "react";
import { useDispatch, useSelector } from "react-redux";

const { Header, Sider } = Layout;

const items = [
  //   {
  //     label: "首页",
  //     key: "/",
  //     icon: <HomeOutlined />,
  //   },
  //   {
  //     label: "文章管理",
  //     key: "/article",
  //     icon: <DiffOutlined />,
  //   },
  //   {
  //     label: "创建文章",
  //     key: "/publish",
  //     icon: <EditOutlined />,
  //   },
  {
    label: "信号调制",
    key: "/matlab",
    icon: <FundOutlined />,
  },
];

const GeekLayout = () => {
  const navigate = useNavigate();
  const MenuClick = (route) => {
    console.log("菜单被点击了", route);
    const path = route.key;
    navigate(path);
  };

  //反向高亮
  //获取当前路由路径
  const location = useLocation();
  const selectedkey = location.pathname;

  return (
    <Layout className="root-layout">
      <Header className="header">
        <div className="logo" />
        <div className="user-info"></div>
      </Header>
      <Layout>
        <Sider width={150} className="site-layout-background">
          <Menu
            mode="inline"
            theme="dark"
            defaultSelectedKeys={selectedkey}
            onClick={MenuClick}
            items={items}
            style={{ height: "100%", borderRight: 0 }}
          ></Menu>
        </Sider>
        <Layout className="layout-content" style={{ padding: 0 }}>
          <Outlet />
        </Layout>
      </Layout>
    </Layout>
  );
};
export default GeekLayout;
