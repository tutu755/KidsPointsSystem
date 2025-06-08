-- 性能优化脚本：为统计报告功能优化数据库
-- Performance Optimization for Analytics Dashboard

-- 1. 添加重要索引 (Add Important Indexes)
-- 历史记录表的复合索引，优化统计查询
CREATE INDEX IF NOT EXISTS idx_history_child_date 
ON history(child_id, date);

CREATE INDEX IF NOT EXISTS idx_history_child_type_date 
ON history(child_id, type, date);

CREATE INDEX IF NOT EXISTS idx_history_date_points 
ON history(date, points) WHERE child_id IS NOT NULL;

-- 任务表索引
CREATE INDEX IF NOT EXISTS idx_tasks_child_type 
ON tasks(child_id, type) WHERE child_id IS NOT NULL;

-- 奖励表索引  
CREATE INDEX IF NOT EXISTS idx_rewards_child 
ON rewards(child_id) WHERE child_id IS NOT NULL;

-- 2. 创建统计视图 (Create Statistical Views)
-- 每日积分汇总视图
CREATE OR REPLACE VIEW daily_points_summary AS
SELECT 
    child_id,
    date,
    SUM(CASE WHEN points > 0 THEN points ELSE 0 END) as positive_points,
    SUM(CASE WHEN points < 0 THEN ABS(points) ELSE 0 END) as negative_points,
    SUM(points) as net_points,
    COUNT(*) as total_actions,
    COUNT(CASE WHEN type = 'daily' THEN 1 END) as daily_tasks,
    COUNT(CASE WHEN type = 'behavior' THEN 1 END) as behavior_tasks,
    COUNT(CASE WHEN type = 'penalties' THEN 1 END) as penalties,
    COUNT(CASE WHEN type = 'redeem' THEN 1 END) as rewards_claimed
FROM history 
WHERE child_id IS NOT NULL
GROUP BY child_id, date
ORDER BY child_id, date;

-- 任务完成统计视图
CREATE OR REPLACE VIEW task_completion_stats AS
SELECT 
    child_id,
    task,
    type,
    COUNT(*) as completion_count,
    SUM(points) as total_points,
    AVG(points) as avg_points,
    MIN(date) as first_completion,
    MAX(date) as last_completion
FROM history 
WHERE child_id IS NOT NULL AND type != 'redeem'
GROUP BY child_id, task, type
ORDER BY child_id, completion_count DESC;

-- 月度汇总视图
CREATE OR REPLACE VIEW monthly_summary AS
SELECT 
    child_id,
    DATE_TRUNC('month', date::date) as month,
    COUNT(*) as total_activities,
    SUM(CASE WHEN points > 0 THEN points ELSE 0 END) as earned_points,
    SUM(CASE WHEN points < 0 THEN ABS(points) ELSE 0 END) as lost_points,
    SUM(points) as net_points,
    COUNT(CASE WHEN type = 'redeem' THEN 1 END) as rewards_claimed
FROM history 
WHERE child_id IS NOT NULL
GROUP BY child_id, DATE_TRUNC('month', date::date)
ORDER BY child_id, month;

-- 3. 创建统计函数 (Create Statistical Functions)
-- 获取孩子指定时间段的详细统计
CREATE OR REPLACE FUNCTION get_child_stats(
    p_child_id BIGINT,
    p_start_date DATE,
    p_end_date DATE
)
RETURNS TABLE (
    total_tasks BIGINT,
    completed_tasks BIGINT,
    total_points_earned NUMERIC,
    total_points_lost NUMERIC,
    net_points NUMERIC,
    rewards_claimed BIGINT,
    completion_rate NUMERIC,
    daily_avg_points NUMERIC
) 
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COUNT(*) FILTER (WHERE type != 'redeem') as total_tasks,
        COUNT(*) FILTER (WHERE type != 'redeem' AND points > 0) as completed_tasks,
        COALESCE(SUM(points) FILTER (WHERE points > 0), 0) as total_points_earned,
        COALESCE(ABS(SUM(points)) FILTER (WHERE points < 0), 0) as total_points_lost,
        COALESCE(SUM(points), 0) as net_points,
        COUNT(*) FILTER (WHERE type = 'redeem') as rewards_claimed,
        CASE 
            WHEN COUNT(*) FILTER (WHERE type != 'redeem') > 0 
            THEN ROUND(COUNT(*) FILTER (WHERE type != 'redeem' AND points > 0)::NUMERIC / COUNT(*) FILTER (WHERE type != 'redeem') * 100, 2)
            ELSE 0 
        END as completion_rate,
        CASE 
            WHEN (p_end_date - p_start_date + 1) > 0 
            THEN ROUND(COALESCE(SUM(points), 0) / (p_end_date - p_start_date + 1), 2)
            ELSE 0 
        END as daily_avg_points
    FROM history 
    WHERE child_id = p_child_id 
    AND date BETWEEN p_start_date AND p_end_date;
END;
$$;

-- 4. 更新表统计信息 (Update Table Statistics)
-- 这有助于查询优化器选择更好的执行计划
ANALYZE history;
ANALYZE tasks;
ANALYZE rewards;
ANALYZE children;

-- 5. 创建清理过期数据的函数 (Optional: Cleanup old data)
-- 可选：清理超过1年的历史数据以保持性能
CREATE OR REPLACE FUNCTION cleanup_old_history(days_to_keep INTEGER DEFAULT 365)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM history 
    WHERE date < CURRENT_DATE - INTERVAL '1 day' * days_to_keep;
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    
    RETURN deleted_count;
END;
$$;

-- 6. 创建数据完整性检查函数
CREATE OR REPLACE FUNCTION check_data_integrity()
RETURNS TABLE (
    check_name TEXT,
    status TEXT,
    details TEXT
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- 检查是否有孤立的历史记录
    RETURN QUERY
    SELECT 
        'Orphaned History Records'::TEXT,
        CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'WARNING' END::TEXT,
        'Found ' || COUNT(*) || ' history records without valid child_id'::TEXT
    FROM history h
    LEFT JOIN children c ON h.child_id = c.id
    WHERE h.child_id IS NOT NULL AND c.id IS NULL;
    
    -- 检查数据分布
    RETURN QUERY
    SELECT 
        'Data Distribution'::TEXT,
        'INFO'::TEXT,
        'Total children: ' || COUNT(DISTINCT child_id) || ', Total history records: ' || COUNT(*)::TEXT
    FROM history 
    WHERE child_id IS NOT NULL;
END;
$$;

-- 执行完成提示
SELECT 'Database optimization completed successfully!' as message; 