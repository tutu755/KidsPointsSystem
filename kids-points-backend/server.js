console.log('server.js started');
const express = require('express');
const fs = require('fs');
const cors = require('cors');
const app = express();
app.use(cors());
app.use(express.json());

const DATA_FILE = './data.json';

// 读取数据
function readData() {
  return JSON.parse(fs.readFileSync(DATA_FILE, 'utf-8'));
}

// 写入数据
function writeData(data) {
  fs.writeFileSync(DATA_FILE, JSON.stringify(data, null, 2));
}

// 获取总积分和历史
app.get('/api/points', (req, res) => {
  const data = readData();
  res.json({ totalPoints: data.totalPoints, history: data.history });
});

// 完成任务/扣分
app.post('/api/points', (req, res) => {
  const { date, taskId, points } = req.body;
  const data = readData();
  if (!data.history[date]) data.history[date] = {};
  data.history[date][taskId] = points;
  data.totalPoints += points;
  writeData(data);
  res.json({ totalPoints: data.totalPoints });
});

// 每天结算，未用完的分数自动累积
app.post('/api/settle', (req, res) => {
  const { date, usedPoints } = req.body;
  const data = readData();
  // 计算当天获得的分数
  const todayPoints = Object.values(data.history[date] || {}).reduce((a, b) => a + b, 0);
  // 剩余分数累积到总积分
  const remain = todayPoints - usedPoints;
  data.totalPoints += remain;
  writeData(data);
  res.json({ totalPoints: data.totalPoints });
});

// 获取小孩姓名
app.get('/api/childName', (req, res) => {
  const data = readData();
  res.json({ childName: data.childName || '' });
});

// 保存小孩姓名
app.post('/api/childName', (req, res) => {
  const { childName } = req.body;
  const data = readData();
  data.childName = childName;
  writeData(data);
  res.json({ success: true });
});

// 获取历史记录
app.get('/api/history', (req, res) => {
  const data = readData();
  res.json(data.history || {});
});

// 添加历史明细
app.post('/api/history', (req, res) => {
  const { date, task, type, points } = req.body;
  const data = readData();
  if (!data.history[date]) {
    data.history[date] = [];
  }
  if (type === 'redeem') {
    // 兑换奖励每次都新增一条记录
    data.history[date].push({ task, type, points });
  } else {
    // 任务/扣分项交替增减
    const existingIndex = data.history[date].findIndex(
      item => item.task === task && item.type === type
    );
    if (existingIndex !== -1) {
      data.history[date].splice(existingIndex, 1);
    } else {
      data.history[date].push({ task, type, points });
    }
  }
  writeData(data);
  res.json(data.history);
});

// 清空某天历史
app.post('/api/clearDay', (req, res) => {
  const { date } = req.body;
  const data = readData();
  if (data.history && data.history[date]) {
    delete data.history[date];
    writeData(data);
  }
  res.json({ success: true });
});

app.listen(3002, () => console.log('Server running on http://localhost:3002'));