# ServiceContainer

插件框架核心 — 替代 DeepSeek Harness 的 Cordis。

## 核心组件

| 组件 | 说明 |
|------|------|
| `Plugin` | 插件生命周期协议 |
| `ServiceContainer` | 类型安全的 DI 容器 |
| `EventBus` | 事件总线 (emit/waterfall/parallel/serial) |
| `PluginManager` | 插件全生命周期管理 |
| `PluginContext` | 插件运行上下文 |
| `CircuitBreaker` | 熔断器 (防雪崩) |

## 插件生命周期

```
loading → initializing → starting → active → stopping → stopped
                                        ↓
                                      failed/errored
```

## 事件分发模式

| 模式 | 说明 | 返回值 |
|------|------|--------|
| `emit` | fire & forget | 无 |
| `waterfall` | 链式处理, 可中断 | AnyCodable? |
| `parallel` | 并行处理 | Void |
| `serial` | 串行处理 | Void |

## 权限等级

| 等级 | 权限 |
|------|------|
| Low | filesystemRead, clipboardAccess |
| Medium | filesystemWrite, networkAccess, keychainAccess |
| High | shellExecution, subprocessSpawn, terminalAccess, screenCapture |
