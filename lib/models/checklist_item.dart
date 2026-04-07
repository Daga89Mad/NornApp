// lib/models/checklist_item.dart

class ChecklistItem {
  final String? id;
  final String eventId;
  final String text;
  final bool isChecked;
  final int position; // para mantener el orden

  const ChecklistItem({
    this.id,
    required this.eventId,
    required this.text,
    this.isChecked = false,
    this.position = 0,
  });

  ChecklistItem copyWith({String? id, bool? isChecked}) {
    return ChecklistItem(
      id: id ?? this.id,
      eventId: eventId,
      text: text,
      isChecked: isChecked ?? this.isChecked,
      position: position,
    );
  }
}
