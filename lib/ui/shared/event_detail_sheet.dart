import 'dart:convert';
import 'package:flutter/material.dart';
import '../../domain/models/event_model.dart';

void showEventDetailSheet(BuildContext context, EventModel event) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Event Details',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          const Divider(),
          _buildDetailRow('Event ID', event.eventId),
          _buildDetailRow('Source', event.source.toUpperCase()),
          _buildDetailRow('Event Type', event.eventType),
          _buildDetailRow('Timestamp', event.timestamp),
          if (event.simSlot != null) _buildDetailRow('SIM Slot', 'Slot ${event.simSlot! + 1} (${event.simName ?? ""})'),
          if (event.simNumber != null) _buildDetailRow('SIM Number', event.simNumber!),
          if (event.instanceName != null) _buildDetailRow('Instance', event.instanceName!),
          if (event.userPhoneNumber != null) _buildDetailRow('Phone Number', event.userPhoneNumber!),
          if (event.userProfileId != null) _buildDetailRow('Profile / User ID', event.userProfileId!),
          if (event.sender != null) _buildDetailRow('Sender', event.sender!),
          if (event.title != null) _buildDetailRow('Title / Subject', event.title!),
          const SizedBox(height: 10),
          const Text('Message Content:', style: TextStyle(fontWeight: FontWeight.bold)),
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: SelectableText(event.message ?? ''),
          ),
          const SizedBox(height: 12),
          _buildDetailRow('Delivery Status', event.deliveryStatus.toUpperCase()),
          _buildDetailRow('Retry Count', event.retryCount.toString()),
          if (event.serverResponse != null) ...[
            const SizedBox(height: 10),
            const Text('Server Response:', style: TextStyle(fontWeight: FontWeight.bold)),
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(event.serverResponse!),
            ),
          ],
          const SizedBox(height: 20),
          const Text('Payload Sent To Server (JSON):', style: TextStyle(fontWeight: FontWeight.bold)),
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(event.toServerPayload()),
              style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildDetailRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        ),
        Expanded(child: SelectableText(value)),
      ],
    ),
  );
}
