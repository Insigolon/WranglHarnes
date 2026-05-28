import 'package:flutter/material.dart';

import '../../agent/harness/tool.dart';

const _kRed = Color(0xFFFF2200);
const _kWhite = Color(0xFFF0EFEB);

class AgentUiWidget extends StatefulWidget {
  final List<AgentStep> steps;
  final int maxSteps;
  final VoidCallback? onCancel;

  const AgentUiWidget({
    super.key,
    required this.steps,
    this.maxSteps = 10,
    this.onCancel,
  });

  @override
  State<AgentUiWidget> createState() => _AgentUiWidgetState();
}

class _AgentUiWidgetState extends State<AgentUiWidget> {
  final _listKey = GlobalKey<AnimatedListState>();
  List<AgentStep> _displayedSteps = [];

  @override
  void didUpdateWidget(covariant AgentUiWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.steps.length > _displayedSteps.length) {
      for (var i = _displayedSteps.length; i < widget.steps.length; i++) {
        _listKey.currentState?.insertItem(i);
      }
    } else if (widget.steps.isEmpty) {
      _displayedSteps = [];
    }
    _displayedSteps = List.from(widget.steps);
  }

  @override
  void initState() {
    super.initState();
    _displayedSteps = List.from(widget.steps);
    if (_displayedSteps.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (var i = 0; i < _displayedSteps.length; i++) {
          _listKey.currentState?.insertItem(i);
        }
      });
    }
  }

  int get _completedCount =>
      widget.steps.where((s) => s.status == StepStatus.completed).length;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: (widget.steps.length * 28).clamp(28, 140).toDouble(),
          child: AnimatedList(
            key: _listKey,
            initialItemCount: _displayedSteps.length,
            shrinkWrap: true,
            itemBuilder: (context, index, animation) {
              if (index >= widget.steps.length) {
                return const SizedBox.shrink();
              }
              return _StepRow(
                step: widget.steps[index],
                animation: animation,
                showCancel:
                    widget.steps[index].status == StepStatus.running &&
                        widget.onCancel != null,
                onCancel: widget.steps[index].status == StepStatus.running
                    ? widget.onCancel
                    : null,
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Row(
            children: [
              const Spacer(),
              Text(
                '$_completedCount / ${widget.maxSteps}',
                style: const TextStyle(
                  color: _kWhite,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  final AgentStep step;
  final Animation<double> animation;
  final bool showCancel;
  final VoidCallback? onCancel;

  const _StepRow({
    required this.step,
    required this.animation,
    this.showCancel = false,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: animation,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        child: Row(
          children: [
            _statusIcon(step.status),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                step.label,
                style: TextStyle(
                  color: step.status == StepStatus.failed
                      ? _kRed
                      : _kWhite,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            if (showCancel)
              GestureDetector(
                onTap: onCancel,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _kRed.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _kRed.withValues(alpha: 0.6),
                      width: 1,
                    ),
                  ),
                  child: const Text(
                    'cancel',
                    style: TextStyle(
                      color: _kRed,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusIcon(StepStatus status) {
    switch (status) {
      case StepStatus.running:
        return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: _kWhite,
          ),
        );
      case StepStatus.completed:
        return const Icon(Icons.check_circle, size: 16, color: Color(0xFF4CAF50));
      case StepStatus.failed:
        return const Icon(Icons.error, size: 16, color: _kRed);
    }
  }
}
