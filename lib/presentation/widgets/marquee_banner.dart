// v3.0.19: MarqueeBanner - Banner quảng cáo tự chạy (text scroll ngang)
import 'dart:async';
import 'package:flutter/material.dart';

class MarqueeBanner extends StatefulWidget {
  final List<String> messages;
  final Color backgroundColor;
  final Color textColor;
  final double height;
  final double fontSize;
  final Duration scrollDuration;

  const MarqueeBanner({
    required this.messages,
    this.backgroundColor = const Color(0xFF00838F),
    this.textColor = Colors.white,
    this.height = 36.0,
    this.fontSize = 12.0,
    this.scrollDuration = const Duration(seconds: 25),
  });

  @override
  State<MarqueeBanner> createState() => _MarqueeBannerState();
}

class _MarqueeBannerState extends State<MarqueeBanner>
    with SingleTickerProviderStateMixin {
  late ScrollController _scrollController;
  late AnimationController _animController;
  late Animation<double> _animation;
  late Timer _timer;
  int _currentMessageIndex = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _animController = AnimationController(
      vsync: this,
      duration: widget.scrollDuration,
    );
    _animation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.linear),
    );
    _animController.addListener(() {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(
          _animController.value * _scrollController.position.maxScrollExtent,
        );
      }
    });
    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // Chuyển message tiếp theo
        setState(() {
          _currentMessageIndex = (_currentMessageIndex + 1) % widget.messages.length;
        });
        _scrollController.jumpTo(0);
        _animController.reset();
        _animController.forward();
      }
    });
    // Bắt đầu scroll sau 500ms
    _timer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _animController.forward();
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _animController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.messages[_currentMessageIndex];
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            widget.backgroundColor,
            widget.backgroundColor.withValues(alpha: 0.8),
          ],
        ),
        border: Border(
          bottom: BorderSide(color: widget.backgroundColor.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Icon(Icons.health_and_safety, color: widget.textColor, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: ListView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                Row(
                  children: [
                    Text(
                      message,
                      style: TextStyle(
                        color: widget.textColor,
                        fontSize: widget.fontSize,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(width: 100),
                    // Duplicate cho marquee mượt
                    Text(
                      message,
                      style: TextStyle(
                        color: widget.textColor.withValues(alpha: 0.0),
                        fontSize: widget.fontSize,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: widget.textColor, size: 14),
            tooltip: 'Đóng',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              setState(() {
                _currentMessageIndex = (_currentMessageIndex + 1) % widget.messages.length;
              });
            },
          ),
        ],
      ),
    );
  }
}
