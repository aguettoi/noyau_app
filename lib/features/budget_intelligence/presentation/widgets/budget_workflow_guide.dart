import 'package:flutter/material.dart';

import '../../../../core/theme/app_design_system.dart';

enum BudgetExperienceKind { preparation, program, simulation, close }

class BudgetWorkflowGuide extends StatelessWidget {
  const BudgetWorkflowGuide({
    super.key,
    required this.title,
    required this.subtitle,
    required this.steps,
    this.currentStep = 0,
    this.kind = BudgetExperienceKind.preparation,
  });

  final String title;
  final String subtitle;
  final List<String> steps;
  final int currentStep;
  final BudgetExperienceKind kind;

  @override
  Widget build(BuildContext context) {
    final color = switch (kind) {
      BudgetExperienceKind.simulation => Theme.of(
        context,
      ).colorScheme.tertiaryContainer,
      BudgetExperienceKind.close => Theme.of(
        context,
      ).colorScheme.secondaryContainer,
      _ => Theme.of(context).colorScheme.primaryContainer,
    };
    return Semantics(
      container: true,
      label: '$title. ${currentStep + 1} / ${steps.length}. $subtitle',
      child: Card(
        key: Key('budget-workflow-${kind.name}'),
        color: color,
        child: Padding(
          padding: AppSpacing.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.xxs),
              Text(subtitle),
              const SizedBox(height: AppSpacing.sm),
              LinearProgressIndicator(
                value: steps.isEmpty ? 0 : (currentStep + 1) / steps.length,
              ),
              const SizedBox(height: AppSpacing.sm),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var index = 0; index < steps.length; index++) ...[
                      Chip(
                        avatar: CircleAvatar(child: Text('${index + 1}')),
                        label: Text(steps[index]),
                        side: index == currentStep
                            ? BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              )
                            : null,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
