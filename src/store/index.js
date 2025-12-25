import { configureStore } from "@reduxjs/toolkit";

const store = configureStore({
  reducer: {
    // 这里可以添加各种 reducer
    // 例如：user: userReducer, etc.
  },
});

export default store;
