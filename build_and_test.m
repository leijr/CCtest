%% PMSM 中性点升压充电模型 - 完整搭建与测试
% 拓扑: 400V DC -> 中性点 -> 三相电感 -> 逆变器 -> 800V DC-Link -> 电池
% 控制: 电压外环PI + 三相交错电流内环PI

%% === 参数定义 ===
Vin    = 400;      % 充电桩输入电压 [V]
Vout   = 800;      % 目标输出电压 [V]
L_val  = 0.15e-3;  % 每相电感 [H] (等效电机绕组)
R_val  = 0.02;     % 每相等效电阻 [Ohm]
Cdc    = 2000e-6;  % DC-Link 电容 [F]
fsw    = 20e3;     % 开关频率 [Hz]
Tsw    = 1/fsw;    % 开关周期
Rbatt  = 0.05;     % 电池内阻 [Ohm]
Pmax   = 50000;    % 最大功率 [W]
Iin_max = Pmax/Vin;% 最大输入电流 [A]
D_nom  = 1 - Vin/Vout;  % 标称占空比 0.5

% 控制参数
Kp_v = 0.5;  Ki_v = 50;    % 电压环PI
Kp_i = 0.4;  Ki_i = 40;    % 电流环PI
Vdc_ref = Vout;

modelName = 'PMSM_NP_Boost';

%% === 1. 创建模型 ===
if bdIsLoaded(modelName), close_system(modelName, 0); end
if exist([modelName '.slx'], 'file'), delete([modelName '.slx']); end

new_system(modelName);
open_system(modelName);
set_param(modelName, 'StopTime', '0.1');
set_param(modelName, 'Solver', 'ode23tb');
set_param(modelName, 'MaxStep', '1e-6');
set_param(modelName, 'RelTol', '1e-4');

%% === 2. Powergui ===
add_block('powerlib/powergui', [modelName '/powergui'], 'Position', [20,20,60,60]);

%% === 3. 主电路模块 ===
% 3.1 400V DC 充电桩
add_block('sps_lib/Sources/DC Voltage Source', [modelName '/DC_Charger'], ...
    'Position', [80,150,120,190], 'Amplitude', num2str(Vin));

% 3.2 三相电感 (等效 PMSM 绕组)
for i = 1:3
    add_block('sps_lib/Passives/Series RLC Branch', [modelName '/L' num2str(i)], ...
        'Position', [200, 120+(i-1)*60, 240, 160+(i-1)*60], ...
        'BranchType', 'L', 'Inductance', num2str(L_val), ...
        'Measurements', 'Branch current');
end

% 3.3 电流传感器 (串联在电感和逆变器之间)
for i = 1:3
    add_block('sps_lib/Sensors and Measurements/Current Measurement', ...
        [modelName '/I' num2str(i) '_sense'], ...
        'Position', [300, 120+(i-1)*60, 330, 160+(i-1)*60]);
end

% 3.4 三相逆变器 (MOSFET)
add_block('sps_lib/Power Electronics/Universal Bridge', [modelName '/Inverter'], ...
    'Position', [400, 100, 460, 260], 'Arms', '3', 'Device', 'MOSFET', ...
    'Ron', '1e-3', 'ForwardVoltages', '[0.5 0.5]');

% 3.5 DC-Link 电容
add_block('sps_lib/Passives/Series RLC Branch', [modelName '/Cdc_link'], ...
    'Position', [550, 80, 590, 120], 'BranchType', 'C', ...
    'Capacitance', num2str(Cdc), 'Setx0', 'on', 'InitialVoltage', num2str(Vin));

% 3.6 800V 电池 (电压源+内阻)
add_block('sps_lib/Sources/DC Voltage Source', [modelName '/Battery_V'], ...
    'Position', [650, 60, 690, 100], 'Amplitude', num2str(Vout));
add_block('sps_lib/Passives/Series RLC Branch', [modelName '/R_batt'], ...
    'Position', [650, 130, 690, 170], 'BranchType', 'R', ...
    'Resistance', num2str(Rbatt));

% 3.7 DC-Link 电压传感器
add_block('sps_lib/Sensors and Measurements/Voltage Measurement', ...
    [modelName '/Vdc_sense'], 'Position', [500, 30, 530, 60]);

% 3.8 接地
add_block('sps_lib/Utilities/Ground', [modelName '/GND_in'],  'Position', [120,380,150,410]);
add_block('sps_lib/Utilities/Ground', [modelName '/GND_out'], 'Position', [550,380,580,410]);

%% === 4. 主电路连线 ===
% 充电桩正极 -> 中性点(三相电感公共端)
add_line(modelName, 'DC_Charger/RConn1', 'L1/LConn1');
add_line(modelName, 'L1/LConn1', 'L2/LConn1');
add_line(modelName, 'L2/LConn1', 'L3/LConn1');
% 充电桩负极 -> 接地
add_line(modelName, 'DC_Charger/LConn1', 'GND_in/LConn1');

% 电感 -> 电流传感器 (注意: L→sensor→Inverter 的顺序)
add_line(modelName, 'L1/RConn1', 'I1_sense/LConn1');
add_line(modelName, 'L2/RConn1', 'I2_sense/LConn1');
add_line(modelName, 'L3/RConn1', 'I3_sense/LConn1');

% 电流传感器 -> 逆变器
add_line(modelName, 'I1_sense/RConn1', 'Inverter/LConn1');
add_line(modelName, 'I2_sense/RConn1', 'Inverter/LConn2');
add_line(modelName, 'I3_sense/RConn1', 'Inverter/LConn3');

% 逆变器直流侧 -> DC-Link -> 电池
add_line(modelName, 'Inverter/RConn1', 'Cdc_link/LConn1');
add_line(modelName, 'Inverter/RConn1', 'Battery_V/RConn1');
add_line(modelName, 'Inverter/RConn2', 'Cdc_link/RConn1');
add_line(modelName, 'Inverter/RConn2', 'R_batt/RConn1');
add_line(modelName, 'Inverter/RConn2', 'GND_out/LConn1');
add_line(modelName, 'Battery_V/LConn1', 'R_batt/LConn1');

% 电压传感器并联在 DC-Link 上
add_line(modelName, 'Cdc_link/LConn1', 'Vdc_sense/LConn1');
add_line(modelName, 'Vdc_sense/LConn2', 'GND_out/LConn1');

%% === 5. 控制器子系统 ===
add_block('simulink/Ports & Subsystems/Subsystem', [modelName '/Controller'], ...
    'Position', [300, 420, 550, 680]);
% 删除默认端口
delete_block([modelName '/Controller/In1']);
delete_block([modelName '/Controller/Out1']);

% 控制器输入: Vdc + 三相电流
add_block('simulink/Ports & Subsystems/In1', [modelName '/Controller/Vdc'], ...
    'Position', [30,40,60,60]);
add_block('simulink/Ports & Subsystems/In1', [modelName '/Controller/I1'], ...
    'Position', [30,90,60,110]);
add_block('simulink/Ports & Subsystems/In1', [modelName '/Controller/I2'], ...
    'Position', [30,140,60,160]);
add_block('simulink/Ports & Subsystems/In1', [modelName '/Controller/I3'], ...
    'Position', [30,190,60,210]);

% 控制器输出: 6路PWM
for i = 1:6
    add_block('simulink/Ports & Subsystems/Out1', ...
        [modelName '/Controller/PWM' num2str(i)], ...
        'Position', [520, 40+(i-1)*35, 550, 60+(i-1)*35]);
end

ctrl = [modelName '/Controller'];

% 5.1 电压外环 PI
add_block('simulink/Sources/Constant', [ctrl '/Vref'], ...
    'Position', [80,40,110,60], 'Value', num2str(Vdc_ref));
add_block('simulink/Math Operations/Subtract', [ctrl '/Verr'], ...
    'Position', [140,40,160,60]);
add_block('simulink/Continuous/PID Controller', [ctrl '/V_PI'], ...
    'Position', [190,30,240,80], 'Controller', 'PI', ...
    'P', num2str(Kp_v), 'I', num2str(Ki_v), ...
    'LimitOutput', 'on', 'UpperSaturationLimit', num2str(Iin_max), ...
    'LowerSaturationLimit', '0');

add_line(ctrl, 'Vref/1', 'Verr/1');
add_line(ctrl, 'Vdc/1', 'Verr/2');
add_line(ctrl, 'Verr/1', 'V_PI/1');

% 5.2 每相电流参考 = 总参考/3
add_block('simulink/Math Operations/Gain', [ctrl '/Iref_div3'], ...
    'Position', [270,35,300,65], 'Gain', '1/3');
add_line(ctrl, 'V_PI/1', 'Iref_div3/1');

% 5.3 三相电流 PI
for i = 1:3
    add_block('simulink/Math Operations/Subtract', [ctrl '/I' num2str(i) 'err'], ...
        'Position', [330, 80+(i-1)*50, 350, 100+(i-1)*50]);
    add_block('simulink/Continuous/PID Controller', [ctrl '/I' num2str(i) '_PI'], ...
        'Position', [370, 70+(i-1)*50, 420, 120+(i-1)*50], ...
        'Controller', 'PI', 'P', num2str(Kp_i), 'I', num2str(Ki_i), ...
        'LimitOutput', 'on', 'UpperSaturationLimit', '1', ...
        'LowerSaturationLimit', '-1');

    add_line(ctrl, 'Iref_div3/1', ['I' num2str(i) 'err/1']);
    add_line(ctrl, ['I' num2str(i) '/1'], ['I' num2str(i) 'err/2']);
    add_line(ctrl, ['I' num2str(i) 'err/1'], ['I' num2str(i) '_PI/1']);
end

% 5.4 三相交错三角载波 (20kHz, 相位偏移 0°/120°/240°)
% 周期 Tsw=50µs, 三角波标准: t∈[0,25]→y=t/25, t∈[25,50]→y=2-t/25
% Phase A (0°):  time=[0 25 50]µs, y=[0 1 0]
% Phase B (120°=16.67µs shift): time=[0 16.67 41.67 50]µs, y=[0.667 0 1 0.667]
% Phase C (240°=33.33µs shift): time=[0 8.333 33.33 50]µs, y=[0.667 1 0 0.667]
carrier_configs = {
    {'[0 25e-6 50e-6]', '[0 1 0]'},                                    % Phase A
    {'[0 16.667e-6 41.667e-6 50e-6]', '[0.6667 0 1 0.6667]'},           % Phase B
    {'[0 8.333e-6 33.333e-6 50e-6]', '[0.6667 1 0 0.6667]'}             % Phase C
};
for i = 1:3
    add_block('simulink/Sources/Repeating Sequence', [ctrl '/Carrier' num2str(i)], ...
        'Position', [330, 220+(i-1)*30, 380, 250+(i-1)*30], ...
        'rep_seq_t', carrier_configs{i}{1}, ...
        'rep_seq_y', carrier_configs{i}{2});
end

% 5.5 占空比映射: PI输出[-1,1] -> 上管duty[0,1]
% D_upper = 0.5 - PI*0.5  (PI正值→减小D→增加升压)
for i = 1:3
    add_block('simulink/Math Operations/Gain', [ctrl '/S' num2str(i)], ...
        'Position', [450, 75+(i-1)*50, 470, 100+(i-1)*50], 'Gain', '-0.5');
    add_block('simulink/Math Operations/Add', [ctrl '/D' num2str(i)], ...
        'Position', [490, 75+(i-1)*50, 510, 100+(i-1)*50], 'Inputs', '++');
    add_block('simulink/Sources/Constant', [ctrl '/C05_' num2str(i)], ...
        'Position', [450, 105+(i-1)*50, 470, 125+(i-1)*50], 'Value', '0.5');

    add_line(ctrl, ['I' num2str(i) '_PI/1'], ['S' num2str(i) '/1']);
    add_line(ctrl, ['S' num2str(i) '/1'], ['D' num2str(i) '/1']);
    add_line(ctrl, ['C05_' num2str(i) '/1'], ['D' num2str(i) '/2']);
end

% 5.6 比较器生成PWM (Duty vs Carrier)
% 使用 Relational Operator: duty > carrier → 上管ON
for i = 1:3
    % 占空比 > 载波 → 上管开
    add_block('simulink/Logic and Bit Operations/Relational Operator', ...
        [ctrl '/Cmp' num2str(i)], 'Position', [550, 75+(i-1)*50, 580, 105+(i-1)*50], ...
        'Operator', '>');

    add_line(ctrl, ['D' num2str(i) '/1'], ['Cmp' num2str(i) '/1']);
    add_line(ctrl, ['Carrier' num2str(i) '/1'], ['Cmp' num2str(i) '/2']);

    % 互补
    add_block('simulink/Logic and Bit Operations/Logical Operator', ...
        [ctrl '/N' num2str(i)], 'Position', [620, 75+(i-1)*50, 650, 105+(i-1)*50], ...
        'Operator', 'NOT');
    add_line(ctrl, ['Cmp' num2str(i) '/1'], ['N' num2str(i) '/1']);
end

% 5.7 输出到PWM端口
add_line(ctrl, 'Cmp1/1', 'PWM1/1');
add_line(ctrl, 'N1/1',   'PWM2/1');
add_line(ctrl, 'Cmp2/1', 'PWM3/1');
add_line(ctrl, 'N2/1',   'PWM4/1');
add_line(ctrl, 'Cmp3/1', 'PWM5/1');
add_line(ctrl, 'N3/1',   'PWM6/1');

%% === 6. 信号连接 (控制器外部) ===
% Vdc 反馈
add_line(modelName, 'Vdc_sense/1', 'Controller/1');
% 三相电流反馈
add_line(modelName, 'I1_sense/1', 'Controller/2');
add_line(modelName, 'I2_sense/1', 'Controller/3');
add_line(modelName, 'I3_sense/1', 'Controller/4');

% PWM Mux -> Inverter gate
add_block('simulink/Signal Routing/Mux', [modelName '/Mux_PWM'], ...
    'Position', [370, 380, 400, 430], 'Inputs', '6');
add_line(modelName, 'Controller/1', 'Mux_PWM/1');
add_line(modelName, 'Controller/2', 'Mux_PWM/2');
add_line(modelName, 'Controller/3', 'Mux_PWM/3');
add_line(modelName, 'Controller/4', 'Mux_PWM/4');
add_line(modelName, 'Controller/5', 'Mux_PWM/5');
add_line(modelName, 'Controller/6', 'Mux_PWM/6');
add_line(modelName, 'Mux_PWM/1', 'Inverter/1');

%% === 7. 示波器 ===
add_block('simulink/Sinks/Scope', [modelName '/Scope'], ...
    'Position', [750, 100, 880, 350], 'NumInputPorts', '4');
add_line(modelName, 'Vdc_sense/1', 'Scope/1');
add_line(modelName, 'I1_sense/1', 'Scope/2');
add_line(modelName, 'I2_sense/1', 'Scope/3');
add_line(modelName, 'I3_sense/1', 'Scope/4');

%% === 8. 配置仿真参数(防过零检测问题) ===
set_param(modelName, 'ZeroCrossAlgorithm', 'Adaptive');
set_param(modelName, 'IgnoredZcDiagnostic', 'none');

% 禁用比较器模块的过零检测
for i = 1:3
    set_param([ctrl '/Cmp' num2str(i)], 'ZeroCross', 'off');
end

save_system(modelName);
fprintf('=== 模型构建完成，开始仿真测试 ===\n');

% 运行仿真
set_param(modelName, 'StopTime', '0.02');
simOut = sim(modelName, 'SimulationMode', 'normal');
fprintf('=== 仿真成功! ===\n');

% 获取仿真数据
tout = simOut.tout;
if ~isempty(tout)
    fprintf('仿真时长: %.3fs, 数据点数: %d\n', tout(end), length(tout));
else
    fprintf('仿真运行完成但无时间序列数据。请检查Scope。\n');
end

% 提示用户
fprintf('\n模型 PMSM_NP_Boost.slx 已就绪!\n');
fprintf('拓扑: 400V DC -> 中性点 -> 三相电感 -> 逆变器 -> 800V DC-Link -> 电池\n');
fprintf('控制: 电压外环PI + 三相交错电流内环PI\n');
