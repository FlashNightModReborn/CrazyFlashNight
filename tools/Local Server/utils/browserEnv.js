// utils/browserEnv.js
const { JSDOM } = require('jsdom');
const webAudioAPI = require('node-web-audio-api');

// 创建一个模拟浏览器环境的 JSDOM 实例
const dom = new JSDOM('<!DOCTYPE html><html><body></body></html>');
global.window = dom.window;
global.document = dom.window.document;
global.navigator = {
    userAgent: 'node.js',
    platform: 'Node'
};
global.AudioContext = webAudioAPI.AudioContext;
global.WebAudioContext = webAudioAPI.WebAudioContext;

// 模拟 localStorage
global.localStorage = {
    getItem: () => null,
    setItem: () => {}
};

// 模拟事件监听方法
global.window.addEventListener = () => {};
global.document.addEventListener = () => {};
global.document.removeEventListener = () => {};
