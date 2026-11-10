// ============================================================
// 我的第一个 Flutter 项目：今天吃什么
// ------------------------------------------------------------
// 学习目标：
// 1. 看懂一个 Flutter 页面的“Widget 树”结构
// 2. 理解 StatelessWidget 和 StatefulWidget 的区别
// 3. 学会用 setState 更新界面
// 4. 熟悉常用布局：Column / Row / Expanded / Padding
// 5. 熟悉常用组件：Text / Card / ListView / TextField / 按钮
// ============================================================

import 'dart:math';
import 'package:flutter/material.dart';

// ---------- 1. 程序入口 ----------
// Dart 程序从 main() 开始执行。
// runApp 把 MyApp 这个 Widget 挂到屏幕上，从此进入 Flutter 的世界。
void main() {
  runApp(const MyApp());
}

// ---------- 2. 根组件（不会变化的部分用 StatelessWidget）----------
// StatelessWidget：没有“状态”的组件，创建后界面内容不会因为数据变化而重建。
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // MaterialApp 是 Material 风格应用的“总开关”：
    // 它提供主题、路由、多语言等全局能力。home 指定首页显示哪个页面。
    return MaterialApp(
      title: '今天吃什么',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        // fromSeed：用一种“种子颜色”自动生成整套协调的配色。
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
      ),
      home: const HomePage(),
    );
  }
}

// ---------- 3. 首页（会变化的部分用 StatefulWidget）----------
// StatefulWidget：界面会随着数据变化而变化时使用。
// 它本身只负责“创建状态”，真正的数据和 build 逻辑写在 State 里。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // 这些就是“状态”：数据一变，界面就要重新绘制。
  // 下划线开头表示私有，只能在本文件内访问。
  final List<String> _foods = <String>[
    '火锅',
    '麻辣香锅',
    '兰州拉面',
    '黄焖鸡米饭',
    '螺蛳粉',
    '寿司',
  ];

  // 输入框的控制器：用来读取用户输入的文字，也能清空输入框。
  final TextEditingController _controller = TextEditingController();

  // 抽中的结果。String? 表示可以为 null（还没抽过时为 null）。
  String? _result;

  // dispose 在页面销毁时调用，用来释放资源（控制器必须释放）。
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // 添加一个选项
  void _addFood() {
    final String text = _controller.text.trim(); // trim 去掉首尾空格
    if (text.isEmpty) {
      _showMessage('先输入一个想吃的菜名');
      return; // 提前结束方法
    }
    setState(() {
      _foods.add(text);
      _controller.clear();
    });
  }

  // 删除指定位置的选项
  void _removeFood(int index) {
    setState(() {
      _foods.removeAt(index);
    });
  }

  // 随机抽取一个
  void _pick() {
    if (_foods.isEmpty) {
      _showMessage('列表是空的，先添加几个想吃的吧');
      return;
    }
    setState(() {
      _result = _foods[Random().nextInt(_foods.length)];
    });
  }

  // 底部弹出提示
  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  // ---------- 4. build：描述“界面长什么样”----------
  // Flutter 的界面就是一棵 Widget 树。
  // 你写的不是命令式的“移动这个按钮”，而是声明式的“界面应该是什么结构”。
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Scaffold 提供页面骨架：标题栏、内容区、底部栏、悬浮按钮等。
      appBar: AppBar(
        title: const Text('今天吃什么'),
        centerTitle: true,
      ),
      // SafeArea 会避开手机顶部的刘海和底部手势区域。
      body: SafeArea(
        // 整个页面放进一个 ListView：
        // 内容超过屏幕时可以滚动，弹出键盘时也不会出现“溢出”警告。
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            _buildResultCard(), // 顶部：显示结果
            const SizedBox(height: 12),
            _buildFoodList(), // 中间：选项列表
            const SizedBox(height: 12),
            _buildInputRow(), // 输入框 + 添加按钮
            const SizedBox(height: 12),
            SizedBox(
              // width: double.infinity 让按钮横向占满
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _pick, // 点击时执行 _pick 方法
                icon: const Icon(Icons.casino),
                label: const Text('帮我选一个'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 把界面拆成小方法，比写一个巨大的 build 更好读。
  Widget _buildResultCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '今天就吃',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              // ?? 是空值合并：如果 _result 是 null，就显示 "？"
              _result ?? '？',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFoodList() {
    if (_foods.isEmpty) {
      return const Center(child: Text('还没有选项，先在上面添加吧'));
    }
    // Column 把每一项竖着排；for 循环可以动态生成一组 Widget。
    return Column(
      children: <Widget>[
        for (int i = 0; i < _foods.length; i++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Text('${i + 1}'),
            title: Text(_foods[i]),
            trailing: IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _removeFood(i),
            ),
          ),
      ],
    );
  }

  Widget _buildInputRow() {
    return Row(
      // Row：把子组件从左到右横着排。
      children: <Widget>[
        Expanded(
          // Expanded 让输入框占满剩余宽度，按钮才不会被挤出去。
          child: TextField(
            controller: _controller,
            decoration: const InputDecoration(
              labelText: '添加一个选项',
              hintText: '例如：烧烤',
              border: OutlineInputBorder(),
            ),
            // 在电脑键盘上按回车也能添加
            onSubmitted: (_) => _addFood(),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          height: 56,
          child: FilledButton.tonal(
            onPressed: _addFood,
            child: const Text('添加'),
          ),
        ),
      ],
    );
  }
}
