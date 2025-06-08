-- 🔍 全面数据库状态检查和修复脚本

-- 1. 检查用户和孩子的关系
SELECT 
  u.email,
  c.id as child_id,
  c.name as child_name,
  c.created_at as child_created,
  c.parent_id
FROM auth.users u
LEFT JOIN children c ON c.parent_id = u.id
ORDER BY u.email, c.created_at;

-- 2. 检查历史记录中的child_id分布
SELECT 
  user_id,
  child_id,
  COUNT(*) as record_count,
  MIN(date) as first_date,
  MAX(date) as last_date,
  SUM(points) as total_points
FROM history
GROUP BY user_id, child_id
ORDER BY user_id, child_id;

-- 3. 检查各表的数据完整性
SELECT 'history' as table_name, COUNT(*) as total_records, COUNT(child_id) as with_child_id
FROM history
UNION ALL
SELECT 'tasks' as table_name, COUNT(*) as total_records, COUNT(child_id) as with_child_id  
FROM tasks
UNION ALL
SELECT 'rewards' as table_name, COUNT(*) as total_records, COUNT(child_id) as with_child_id
FROM rewards;

-- 4. 🔧 修复历史记录的child_id
-- 为每个用户的历史记录分配给第一个孩子
UPDATE history 
SET child_id = (
  SELECT c.id 
  FROM children c 
  WHERE c.parent_id = history.user_id 
  ORDER BY c.created_at ASC 
  LIMIT 1
)
WHERE child_id IS NULL
AND user_id IN (SELECT DISTINCT parent_id FROM children);

-- 5. 🔧 修复任务的child_id  
UPDATE tasks
SET child_id = (
  SELECT c.id 
  FROM children c 
  WHERE c.parent_id = tasks.user_id 
  ORDER BY c.created_at ASC 
  LIMIT 1
)
WHERE child_id IS NULL
AND user_id IN (SELECT DISTINCT parent_id FROM children);

-- 6. 🔧 修复奖励的child_id
UPDATE rewards
SET child_id = (
  SELECT c.id 
  FROM children c 
  WHERE c.parent_id = rewards.user_id 
  ORDER BY c.created_at ASC 
  LIMIT 1
)
WHERE child_id IS NULL
AND user_id IN (SELECT DISTINCT parent_id FROM children);

-- 7. 验证修复结果
SELECT 
  c.name as child_name,
  c.id as child_id,
  COUNT(DISTINCT h.id) as history_count,
  COUNT(DISTINCT t.id) as task_count, 
  COUNT(DISTINCT r.id) as reward_count,
  COALESCE(SUM(h.points), 0) as total_points
FROM children c
LEFT JOIN history h ON h.child_id = c.id
LEFT JOIN tasks t ON t.child_id = c.id  
LEFT JOIN rewards r ON r.child_id = c.id
GROUP BY c.id, c.name
ORDER BY c.id;

-- 8. 🔧 临时禁用RLS政策（用于紧急修复）
ALTER TABLE children DISABLE ROW LEVEL SECURITY;
ALTER TABLE history DISABLE ROW LEVEL SECURITY;  
ALTER TABLE tasks DISABLE ROW LEVEL SECURITY;
ALTER TABLE rewards DISABLE ROW LEVEL SECURITY;

-- 9. 检查是否还有NULL的child_id记录
SELECT 'Remaining NULL child_id records:' as status;
SELECT 'history' as table_name, COUNT(*) as null_child_id_count FROM history WHERE child_id IS NULL
UNION ALL
SELECT 'tasks' as table_name, COUNT(*) as null_child_id_count FROM tasks WHERE child_id IS NULL  
UNION ALL
SELECT 'rewards' as table_name, COUNT(*) as null_child_id_count FROM rewards WHERE child_id IS NULL; 