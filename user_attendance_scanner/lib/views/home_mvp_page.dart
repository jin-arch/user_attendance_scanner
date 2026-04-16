import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/home_page_controller.dart';
import '../site_model.dart';

class HomeMvpPage extends GetView<HomePageController> {
  const HomeMvpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Scanner'),
        actions: [
          IconButton(
            tooltip: 'Sync employees',
            onPressed: () => controller.manualSync(),
            icon: const Icon(Icons.sync),
          ),
          IconButton(
            tooltip: 'Reconnect device',
            onPressed: () => controller.connectDevice(),
            icon: const Icon(Icons.usb),
          ),
        ],
      ),
      body: Obx(() {
        final error = controller.errorMessage.value;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (error.isNotEmpty)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  title: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: controller.clearError,
                  ),
                ),
              ),

            _SiteSelector(
              sites: controller.sites.toList(growable: false),
              selectedSite: controller.selectedSite.value,
              isLoading: controller.isLoadingSites.value,
              onSelected: (site) => controller.selectSite(site),
            ),

            const SizedBox(height: 12),
            Card(
              child: ListTile(
                title: const Text('Employees'),
                subtitle: Text('${controller.employees.length} loaded'),
                trailing: controller.isLoadingEmployees.value
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
              ),
            ),

            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: Icon(
                  controller.isConnected.value ? Icons.check_circle : Icons.error,
                  color: controller.isConnected.value ? Colors.green : Colors.red,
                ),
                title: Text(controller.isConnected.value ? 'Device connected' : 'Device not connected'),
                subtitle: Text(controller.statusMessage.value.isEmpty
                    ? 'Ready'
                    : controller.statusMessage.value),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (controller.isSearching.value)
                      const Padding(
                        padding: EdgeInsets.only(right: 12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    FilledButton.tonal(
                      onPressed: controller.isConnected.value
                          ? () => controller.restartScanning()
                          : () => controller.connectDevice(),
                      child: Text(controller.isConnected.value ? 'Restart scan' : 'Connect'),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),
            Card(
              child: ListTile(
                title: const Text('Scanner'),
                subtitle: Text(controller.isScanning.value ? 'Scanning…' : 'Idle'),
                trailing: controller.isScanning.value
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
              ),
            ),

            const SizedBox(height: 12),
            Card(
              child: ListTile(
                title: const Text('Last scan result'),
                subtitle: Text(controller.lastScanResult.value?.toString() ?? 'None'),
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _SiteSelector extends StatelessWidget {
  const _SiteSelector({
    required this.sites,
    required this.selectedSite,
    required this.isLoading,
    required this.onSelected,
  });

  final List<Site> sites;
  final Site? selectedSite;
  final bool isLoading;
  final ValueChanged<Site> onSelected;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: const Text('Site'),
        subtitle: isLoading
            ? const Text('Loading sites…')
            : DropdownButtonHideUnderline(
                child: DropdownButton<Site>(
                  isExpanded: true,
                  value: selectedSite,
                  hint: const Text('Select a site'),
                  items: sites
                      .map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text(s.name),
                        ),
                      )
                      .toList(),
                  onChanged: (site) {
                    if (site != null) onSelected(site);
                  },
                ),
              ),
      ),
    );
  }
}
