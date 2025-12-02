import { useState, useEffect } from "react"
import { getChannelAPI } from "../apis/article"

function useChannel() {
  // 1. 获取频道列表所有的逻辑
  const [channelList, setChannelList] = useState([])
  useEffect(() => {
    const getChannelList = async () => {
      const res = await getChannelAPI();
      setChannelList(res.data.channels);
    };
    getChannelList();
  }, [])
  // 2. 把组件中要用到的数据return出去
  return { channelList }
}

export { useChannel }