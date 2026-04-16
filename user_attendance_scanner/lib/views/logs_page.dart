// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/local_db.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key, this.siteId});

  final String? siteId;

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = false;
  String _searchQuery = '';
  String _selectedFilter = 'All';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLogs();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    if (widget.siteId == null || widget.siteId!.isEmpty) return;
    
    setState(() => _isLoading = true);
    try {
      // Get properly formatted attendance logs from timelog_cache
      final logs = await LocalDb.getAttendanceLogsForSite(widget.siteId!);
      
      setState(() {
        _logs = logs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading logs: $e')),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredLogs {
    var filtered = _logs;
    
    // Apply type filter
    if (_selectedFilter != 'All') {
      filtered = filtered.where((log) {
        final type = (log['type'] ?? '').toString().toLowerCase();
        return type.contains(_selectedFilter.toLowerCase());
      }).toList();
    }
    
    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((log) {
        final empId = (log['employee_id'] ?? '').toString().toLowerCase();
        final empName = (log['employee_name'] ?? '').toString().toLowerCase();
        return empId.contains(_searchQuery) || empName.contains(_searchQuery);
      }).toList();
    }
    
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF092238),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Time Logs',
          style: TextStyle(
            color: Colors.white,
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadLogs,
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/Main BG.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(w * 0.02),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(w * 0.04),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0A2240).withOpacity(0.9),
                  borderRadius: BorderRadius.circular(w * 0.04),
                ),
                child: Column(
                  children: [
                    // Search Bar
                    Padding(
                      padding: EdgeInsets.all(w * 0.02),
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Search logs...',
                          hintStyle: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                          ),
                          prefixIcon: const Icon(Icons.search, color: Colors.white70),
                          filled: true,
                          fillColor: const Color(0xFF1A3A5C),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(w * 0.02),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    
                    // Filter Chips
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: w * 0.02),
                      child: Row(
                        children: [
                          _buildFilterChip('All'),
                          SizedBox(width: w * 0.01),
                          _buildFilterChip('Time In'),
                          SizedBox(width: w * 0.01),
                          _buildFilterChip('Time Out'),
                        ],
                      ),
                    ),
                    
                    const Divider(color: Color(0xFF3E7DDD)),
                    
                    // Logs List
                    Expanded(
                      child: _isLoading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFF3FA9F5),
                              ),
                            )
                          : _filteredLogs.isEmpty
                              ? Center(
                                  child: Text(
                                    'No logs found',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.6),
                                      fontSize: 16,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: _filteredLogs.length,
                                  itemBuilder: (context, index) {
                                    final log = _filteredLogs[index];
                                    final type = (log['type'] ?? '').toString().toLowerCase();
                                    final isTimeIn = type.contains('in');
                                    
                                    return ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: isTimeIn 
                                            ? Colors.green 
                                            : Colors.orange,
                                        child: Icon(
                                          isTimeIn ? Icons.login : Icons.logout,
                                          color: Colors.white,
                                        ),
                                      ),
                                      title: Text(
                                        log['employee_name'] ?? 'Unknown',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'ID: ${log['employee_id'] ?? 'N/A'}',
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(0.7),
                                            ),
                                          ),
                                          if (log['period'] != null)
                                            Text(
                                              '${log['period']}',
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(0.6),
                                                fontSize: 12,
                                              ),
                                            ),
                                        ],
                                      ),
                                      trailing: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            log['type'] ?? 'Unknown',
                                            style: TextStyle(
                                              color: isTimeIn ? Colors.green : Colors.orange,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            log['time_only'] ?? _formatTimestamp(log['timestamp']),
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(0.6),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _selectedFilter == label;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedFilter = label;
        });
      },
      backgroundColor: const Color(0xFF1A3A5C),
      selectedColor: const Color(0xFF3FA9F5),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.white.withOpacity(0.8),
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    try {
      final date = DateTime.parse(timestamp.toString());
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return timestamp.toString();
    }
  }
}
