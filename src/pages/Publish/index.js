import {
  Card,
  Breadcrumb,
  Form,
  Button,
  Radio,
  Input,
  Upload,
  Space,
  Select,
} from "antd";
import { PlusOutlined } from "@ant-design/icons";
import { Link } from "react-router-dom";
import "./index.scss";
import ReactQuill from "react-quill-new";
import "react-quill-new/dist/quill.snow.css";
import { getChannelAPI } from "@/apis/article";
import { use, useEffect, useState } from "react";
import { createArticleAPI } from "@/apis/article";
import { message } from "antd";
import { useChannel } from "@/hooks/useChannel";
import { useSearchParams } from "react-router-dom";
import { getArticleById, updateArticleAPI } from "@/apis/article";

const { Option } = Select;

const Publish = () => {
  const { channelList } = useChannel()

  // 表单提交
  const onFinish = (values) => {
    //校验上传的图片数量（imageList的长度）是否与所选的（imageType）一致
    if (imageList.length !== imageType) return message.warning('封面类型和图片数量不匹配')
    console.log(values)
    const { title, content, channel_id } = values
    const data = {
      title,
      content,
      cover: {
        type: imageType,
        // 这个只是处理了新增的，如果是原来的图片，需要处理
        images: imageList.map(item => {
          if (item.response) {
            return item.response.data.url
          }
          else {
            return item.url
          }

        })
      },
      channel_id
    }
    //处理调用不同接口 新增调用新增接口 修改调用修改接口
    if (articleId) {
      data.id = articleId
      //调用修改接口
      updateArticleAPI(data)
    } else {
      createArticleAPI(data)
    }

  }
  //上传图片
  const [imageList, setImageList] = useState([])
  const onChange = (value) => {
    console.log('成功', value)
    setImageList(value.fileList)
  }
  //切换图片个数
  const [imageType, setImageType] = useState(0)
  const onTypeChange = (value) => {
    console.log('切换图片个数')
    const res = value.target.value
    console.log(res);
    setImageType(res)

  }
  //回填数据
  const [searchParams] = useSearchParams()
  const articleId = searchParams.get('id')
  const [form] = Form.useForm()
  useEffect(() => {
    //获取id
    //获取实例回填
    async function getArticleDetail() {
      const res = await getArticleById(articleId)
      const data = res.data
      console.log(data)

      form.setFieldsValue({
        //因为set方法要求传入对象
        ...data,
        type: data.cover.type

      })

      //回填图片
      setImageType(data.cover.type)
      setImageList(data.cover.images.map(url => { return { url } }))
    }
    if (articleId) {
      getArticleDetail()
    }
  }, [articleId, form])
  return (
    <div className="publish">
      <Card
        title={
          <Breadcrumb
            items={[
              { title: <Link to={"/"}>首页</Link> },
              { title: `${articleId ? '编辑文章' : '发布文章'}` },
            ]}
          />
        }
      >
        <Form
          labelCol={{ span: 4 }}
          wrapperCol={{ span: 16 }}
          initialValues={{ type: 0 }}
          onFinish={onFinish}
          form={form}
        >
          <Form.Item
            label="标题"
            name="title"
            rules={[{ required: true, message: "请输入文章标题" }]}
          >
            <Input placeholder="请输入文章标题" style={{ width: 400 }} />
          </Form.Item>
          <Form.Item
            label="频道"
            name="channel_id"
            rules={[{ required: true, message: "请选择文章频道" }]}
          >
            <Select placeholder="请选择文章频道" style={{ width: 400 }}>
              {/* values的值在用户选中后自动收集起来座位接口的提交字段 */}
              {channelList.map((item) => (
                <Option value={item.id} key={item.id}>
                  {item.name}
                </Option>
              ))}
            </Select>
          </Form.Item>
          <Form.Item label="封面">
            <Form.Item name="type">
              <Radio.Group onChange={onTypeChange}>
                <Radio value={1}>单图</Radio>
                <Radio value={3}>三图</Radio>
                <Radio value={0}>无图</Radio>
              </Radio.Group>
            </Form.Item>
            {imageType > 0 && <Upload
              listType="picture-card"
              maxCount={imageType}
              showUploadList
              action={'http://geek.itheima.net/v1_0/upload'}
              name="image"
              onChange={onChange}
              fileList={imageList}
            >
              <div style={{ marginTop: 8 }}>
                <PlusOutlined />
              </div>
            </Upload>}
          </Form.Item>
          <Form.Item
            label="内容"
            name="content"
            rules={[{ required: true, message: "请输入文章内容" }]}
          >
            {/* 富文本编辑器 */}
            <ReactQuill
              className="publish-quill"
              theme="snow"
              placeholder="请输入文章内容"
            />
          </Form.Item>

          <Form.Item wrapperCol={{ offset: 4 }}>
            <Space>
              <Button size="large" type="primary" htmlType="submit">
                发布文章
              </Button>
            </Space>
          </Form.Item>
        </Form>
      </Card>
    </div>
  );
};

export default Publish;
