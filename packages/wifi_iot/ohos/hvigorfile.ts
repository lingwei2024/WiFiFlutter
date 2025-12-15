import path from 'path';
import { appTasks } from '@ohos/hvigor-ohos-plugin';

export default {
    system: appTasks, // 内置系统插件，必须存在
    plugins: []       // 自定义插件可以为空
};