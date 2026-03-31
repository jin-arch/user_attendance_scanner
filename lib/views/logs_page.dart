import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
      final logs = await LocalDb.getAllTimelogsForSite(widget.siteId!);
      setState(() {
        _logs = logs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading logs: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredLogs {
    var filtered = _logs;
    
    // Apply filter
    if (_selectedFilter != 'All') {
      filtered = filtered.where((log) {
        final type = _getLogType(log);
        return type == _selectedFilter;
      }).toList();
    }
    
    // Apply search
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((log) {
        final employeeId = (log['employee_id'] as String? ?? '').toLowerCase();
        final employeeName = (log['employee_name'] as String? ?? '').toLowerCase();
        final date = (log['timelog_date'] as String? ?? '').toLowerCase();
        return employeeId.contains(_searchQuery) || 
               employeeName.contains(_searchQuery) ||
               date.contains(_searchQuery);
      }).toList();
    }
    
    // Sort by date (newest first)
    filtered.sort((a, b) {
      final dateA = a['timelog_date'] as String? ?? '';
      final dateB = b['timelog_date'] as String? ?? '';
      return dateB.compareTo(dateA);
    });
    
    return filtered;
  }

  String _getLogType(Map<String, dynamic> log) {
    final timeInMorning = _pickFirst(log, ['timeInMorning', 'timeinmorning', 'time_in_morning']);
    final timeOutMorning = _pickFirst(log, ['timeOutMorning', 'timeoutmorning', 'time_out_morning']);
    final timeInAfternoon = _pickFirst(log, ['timeInAfternoon', 'timeinafternoon', 'time_in_afternoon']);
    final timeOutAfternoon = _pickFirst(log, ['timeOutAfternoon', 'timeoutafternoon', 'time_out_afternoon']);
    
    final hasIn = !_isBlank(timeInMorning) || !_isBlank(timeInAfternoon);
    final hasOut = !_isBlank(timeOutMorning) || !_isBlank(timeOutAfternoon);
    
    if (hasIn && hasOut) return 'Complete';
    if (hasIn) return 'Time In';
    if (hasOut) return 'Time Out';
    return 'No Log';
  }

  String _pickFirst(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }
    return '';
  }

  bool _isBlank(String value) {
    final text = value.trim();
    return text.isEmpty ||
        text == '00:00:00' ||
        text == '0' ||
        text.toLowerCase() == 'null';
  }

  Color _getLogTypeColor(String type) {
    switch (type) {
      case 'Complete':
        return const Color(0xFF4CAF50);
      case 'Time In':
        return const Color(0xFF2196F3);
      case 'Time Out':
        return const Color(0xFFFF9800);
      default:
        return const Color(0xFF9E9E9E);
    }
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
        title: const Text(
          'Attendance Logs',
          style: TextStyle(
            color: Colors.white,
            fontFamily: 'TRTCENZODEMO',
            fontSize: 24,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: _loadLogs,
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refresh',
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
            child: Column(
              children: [
                // Search and Filter Row
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: w * 0.02),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF3E7DDD)),
                        ),
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Poppins',
                            fontSize: 16,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Search logs...',
                            hintStyle: TextStyle(
                              color: Colors.white70,
                              fontFamily: 'Poppins',
                            ),
                            border: InputBorder.none,
                            prefixIcon: Icon(Icons.search, color: Colors.white70),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: w * 0.01),
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: w * 0.01),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF3E7DDD)),
                        ),
                        child: DropdownButton<String>(
                          value: _selectedFilter,
                          dropdownColor: const Color(0xFF092238),
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Poppins',
                            fontSize: 14,
                          ),
                          underline: const SizedBox(),
                          isExpanded: true,
                          items: ['All', 'Complete', 'Time In', 'Time Out', 'No Log']
                              .map((filter) => DropdownMenuItem<String>(
                                    value: filter,
                                    child: Text(filter),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedFilter = value!;
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: h * 0.02),
                
                // Log Count
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: w * 0.03,
                    vertical: h * 0.01,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B2742).withOpacity(0.8),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.list_alt_outlined,
                        color: Color(0xFF3FA9F5),
                        size: 20,
                      ),
                      SizedBox(width: w * 0.01),
                      Text(
                        'Total Logs: ${_filteredLogs.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'Poppins',
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: h * 0.02),
                
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
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.history,
                                    color: Colors.white70,
                                    size: 64,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _searchQuery.isEmpty && _selectedFilter == 'All'
                                        ? 'No logs found'
                                        : 'No logs match your criteria',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontFamily: 'Poppins',
                                      fontSize: 18,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: _filteredLogs.length,
                              itemBuilder: (context, index) {
                                final log = _filteredLogs[index];
                                return _buildLogCard(log, w, h);
                              },
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogCard(Map<String, dynamic> log, double w, double h) {
    final employeeId = log['employee_id'] as String? ?? 'N/A';
    final employeeName = log['employee_name'] as String? ?? 'Unknown';
    final date = log['timelog_date'] as String? ?? 'N/A';
    final logType = _getLogType(log);
    final typeColor = _getLogTypeColor(logType);
    
    final timeInMorning = _pickFirst(log, ['timeinmorning', 'timeInMorning', 'time_in_morning']);
    final timeOutMorning = _pickFirst(log, ['timeoutmorning', 'timeOutMorning', 'time_out_morning']);
    final timeInAfternoon = _pickFirst(log, ['timeinafternoon', 'timeInAfternoon', 'time_in_afternoon']);
    final timeOutAfternoon = _pickFirst(log, ['timeoutafternoon', 'timeOutAfternoon', 'time_out_afternoon']);
    
    final firstIn = !_isBlank(timeInMorning)
        ? timeInMorning
        : (!_isBlank(timeInAfternoon) ? timeInAfternoon : '-');
    final lastOut = !_isBlank(timeOutAfternoon)
        ? timeOutAfternoon
        : (!_isBlank(timeOutMorning) ? timeOutMorning : '-');

    return Container(
      margin: EdgeInsets.only(bottom: h * 0.01),
      padding: EdgeInsets.all(w * 0.02),
      decoration: BoxDecoration(
        color: const Color(0xFF0B2742).withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: typeColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              // Employee Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employeeName.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'TRTCENZODEMO',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: h * 0.003),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: w * 0.02,
                        vertical: h * 0.002,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1D7CFF),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'ID: $employeeId',
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'CEORUSE',
                          fontSize: 10,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              // Status Badge
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: w * 0.02,
                  vertical: h * 0.008,
                ),
                decoration: BoxDecoration(
                  color: typeColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  logType,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: h * 0.01),
          
          // Timeline Visual
          _buildTimeline(w, h, timeInMorning, timeOutMorning, timeInAfternoon, timeOutAfternoon),
          
          SizedBox(height: h * 0.01),
          
          // Date and Times
          Container(
            padding: EdgeInsets.all(w * 0.015),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      color: Color(0xFF3FA9F5),
                      size: 16,
                    ),
                    SizedBox(width: w * 0.01),
                    Text(
                      date,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: h * 0.008),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildTimeItem('IN', firstIn, const Color(0xFF4CAF50), w),
                    _buildTimeItem('OUT', lastOut, const Color(0xFFFF9800), w),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline(double w, double h, String? timeInMorning, String? timeOutMorning, 
      String? timeInAfternoon, String? timeOutAfternoon) {
    final hasInMorning = !_isBlank(timeInMorning ?? '');
    final hasOutMorning = !_isBlank(timeOutMorning ?? '');
    final hasInAfternoon = !_isBlank(timeInAfternoon ?? '');
    final hasOutAfternoon = !_isBlank(timeOutAfternoon ?? '');
    
    return Container(
      height: h * 0.06,
      child: Row(
        children: [
          // Morning Session
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      // Time In
                      Expanded(
                        child: Container(
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: hasInMorning ? const Color(0xFF4CAF50) : Colors.grey,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              if (hasInMorning) ...[
                                SizedBox(height: h * 0.005),
                                Text(
                                  timeInMorning!,
                                  style: const TextStyle(
                                    color: Color(0xFF4CAF50),
                                    fontSize: 10,
                                    fontFamily: 'CEORUSE',
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      // Connection Line
                      Expanded(
                        child: Container(
                          height: 2,
                          color: (hasInMorning && hasOutMorning) ? const Color(0xFF4CAF50) : Colors.grey.withOpacity(0.3),
                        ),
                      ),
                      // Time Out
                      Expanded(
                        child: Container(
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: hasOutMorning ? const Color(0xFFFF9800) : Colors.grey,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              if (hasOutMorning) ...[
                                SizedBox(height: h * 0.005),
                                Text(
                                  timeOutMorning!,
                                  style: const TextStyle(
                                    color: Color(0xFFFF9800),
                                    fontSize: 10,
                                    fontFamily: 'CEORUSE',
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: h * 0.005),
                const Text(
                  'Morning',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontFamily: 'Poppins',
                  ),
                ),
              ],
            ),
          ),
          
          // Divider
          SizedBox(width: w * 0.02),
          Container(
            width: 1,
            height: h * 0.04,
            color: Colors.white.withOpacity(0.2),
          ),
          SizedBox(width: w * 0.02),
          
          // Afternoon Session
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      // Time In
                      Expanded(
                        child: Container(
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: hasInAfternoon ? const Color(0xFF4CAF50) : Colors.grey,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              if (hasInAfternoon) ...[
                                SizedBox(height: h * 0.005),
                                Text(
                                  timeInAfternoon!,
                                  style: const TextStyle(
                                    color: Color(0xFF4CAF50),
                                    fontSize: 10,
                                    fontFamily: 'CEORUSE',
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      // Connection Line
                      Expanded(
                        child: Container(
                          height: 2,
                          color: (hasInAfternoon && hasOutAfternoon) ? const Color(0xFF4CAF50) : Colors.grey.withOpacity(0.3),
                        ),
                      ),
                      // Time Out
                      Expanded(
                        child: Container(
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: hasOutAfternoon ? const Color(0xFFFF9800) : Colors.grey,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              if (hasOutAfternoon) ...[
                                SizedBox(height: h * 0.005),
                                Text(
                                  timeOutAfternoon!,
                                  style: const TextStyle(
                                    color: Color(0xFFFF9800),
                                    fontSize: 10,
                                    fontFamily: 'CEORUSE',
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: h * 0.005),
                const Text(
                  'Afternoon',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontFamily: 'Poppins',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeItem(String label, String time, Color color, double w) {
    final size = MediaQuery.sizeOf(context);
    final h = size.height;
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: color,
            fontFamily: 'Poppins',
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: h * 0.003),
        Text(
          time,
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'CEORUSE',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}
