%% 整理 PMSM_NP_Boost 模型布局，提高可读性
modelName = 'PMSM_NP_Boost';
load_system(modelName);

%% === 顶层布局 ===
% 坐标网格: X 方向每级 150px，Y 方向每行 50px
% 方块尺寸: [x, y, x+w, y+h]

% --- 电源和接地区域 (左侧) ---
set_param([modelName '/DC_Charger'], 'Position', [50, 200, 110, 260]);
set_param([modelName '/GND_in'],     'Position', [80, 350, 110, 380]);
set_param([modelName '/powergui'],   'Position', [30, 30, 70, 70]);

% --- 电感区域 (中性点) ---
set_param([modelName '/L1'], 'Position', [180, 180, 220, 220]);
set_param([modelName '/L2'], 'Position', [180, 240, 220, 280]);
set_param([modelName '/L3'], 'Position', [180, 300, 220, 340]);

% --- 电流传感器 ---
set_param([modelName '/I1_sense'], 'Position', [290, 180, 320, 220]);
set_param([modelName '/I2_sense'], 'Position', [290, 240, 320, 280]);
set_param([modelName '/I3_sense'], 'Position', [290, 300, 320, 340]);

% --- 逆变器 ---
set_param([modelName '/Inverter'], 'Position', [400, 180, 470, 350]);

% --- DC-Link 和电池 (右侧) ---
set_param([modelName '/Cdc_link'],  'Position', [560, 180, 600, 220]);
set_param([modelName '/Vdc_sense'], 'Position', [530, 130, 560, 160]);
set_param([modelName '/Battery_V'], 'Position', [660, 130, 720, 180]);
set_param([modelName '/R_batt'],    'Position', [660, 200, 720, 240]);
set_param([modelName '/GND_out'],   'Position', [560, 320, 600, 350]);

% --- 控制器和信号 ---
set_param([modelName '/Controller'], 'Position', [400, 400, 600, 600]);
set_param([modelName '/Mux_PWM'],    'Position', [350, 420, 380, 480]);
set_param([modelName '/Scope'],      'Position', [750, 180, 900, 420]);

%% === 整理子系统的内部连线 ===
% Simulink 自动排列
Simulink.BlockDiagram.arrangeSystem([modelName '/Controller']);

%% === 顶层也需要自动路由 ===
Simulink.BlockDiagram.arrangeSystem(modelName);

%% === Controller 内部更精细的布局 ===
ctrl = [modelName '/Controller'];
% 输入端口 (左侧列)
y_in = [40, 100, 150, 200];
in_names = {'Vdc', 'I1', 'I2', 'I3'};
for i = 1:4
    set_param([ctrl '/' in_names{i}], 'Position', [30, y_in(i)+10, 60, y_in(i)+30]);
end

% 电压参考和误差
set_param([ctrl '/Vref'], 'Position', [80, 35, 120, 60]);
set_param([ctrl '/Verr'], 'Position', [150, 40, 180, 60]);
set_param([ctrl '/V_PI'], 'Position', [210, 30, 270, 75]);
set_param([ctrl '/Iref_div3'], 'Position', [300, 40, 330, 65]);

% 电流误差和PI (每个相位一行)
for i = 1:3
    y = 90 + (i-1)*65;
    set_param([ctrl '/I' num2str(i) 'err'], 'Position', [360, y+5, 390, y+25]);
    set_param([ctrl '/I' num2str(i) '_PI'], 'Position', [420, y, 470, y+40]);

    % 占空比映射
    set_param([ctrl '/S' num2str(i)],   'Position', [510, y+5, 530, y+25]);
    set_param([ctrl '/C05_' num2str(i)],'Position', [510, y+30, 530, y+50]);
    set_param([ctrl '/D' num2str(i)],   'Position', [550, y+5, 570, y+45]);

    % 载波
    set_param([ctrl '/Carrier' num2str(i)], 'Position', [510, y-20, 550, y]);

    % PWM比较器
    set_param([ctrl '/Cmp' num2str(i)], 'Position', [600, y+5, 630, y+25]);
    set_param([ctrl '/N' num2str(i)],   'Position', [660, y+5, 690, y+25]);
end

% 输出端口 (右侧列)
for i = 1:6
    y = 40 + (i-1)*35;
    set_param([ctrl '/PWM' num2str(i)], 'Position', [740, y+5, 770, y+25]);
end

%% === 再次自动排列优化线束 ===
Simulink.BlockDiagram.arrangeSystem(ctrl);
Simulink.BlockDiagram.arrangeSystem(modelName);

%% === 保存 ===
save_system(modelName);
fprintf('布局整理完成!\n');
fprintf('  - 顶层: 电源→电感→传感器→逆变器→DC-Link→电池 从左到右排列\n');
fprintf('  - 控制器: 信号从左到右流动 (输入→PI→占空比→PWM→输出)\n');
fprintf('  - 线束已自动路由优化\n');
