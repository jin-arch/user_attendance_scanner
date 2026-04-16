// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/local_db.dart';

class DatabasePage extends StatefulWidget {
  const DatabasePage({super.key, this.siteId});

  final String? siteId;

  @override
  State<DatabasePage> createState() => _DatabasePageState();
}

class _DatabasePageState extends State<DatabasePage> {
  List<Map<String, dynamic>> _employees = [];
  bool _isLoading = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadEmployees();
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

  Future<void> _loadEmployees() async {
    if (widget.siteId == null || widget.siteId!.isEmpty) return;
    
    setState(() => _isLoading = true);
    try {
      final employees = await LocalDb.getEmployeesBySite(widget.siteId!);
      setState(() {
        _employees = employees;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading employees: $e')),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _uniqueEmployees {
    // Group by employee_id to show unique employees with fingerprint count
    final Map<String, Map<String, dynamic>> grouped = {};
    for (final emp in _employees) {
      final empId = emp['employee_id'] as String;
      if (grouped.containsKey(empId)) {
        grouped[empId]!['fingerprint_count'] = (grouped[empId]!['fingerprint_count'] as int) + 1;
      } else {
        grouped[empId] = {
          'employee_id': empId,
          'employee_name': emp['employee_name'],
          'site_id': emp['site_id'],
          'fingerprint_count': 1,
        };
      }
    }
    return grouped.values.toList();
  }

  List<Map<String, dynamic>> get _filteredEmployees {
    final unique = _uniqueEmployees;
    if (_searchQuery.isEmpty) return unique;
    return unique.where((emp) {
      final empId = (emp['employee_id'] ?? '').toString().toLowerCase();
      final empName = (emp['employee_name'] ?? '').toString().toLowerCase();
      return empId.contains(_searchQuery) || empName.contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;

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
          'Employee Database',
          style: TextStyle(
            color: Colors.white,
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadEmployees,
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
                          hintText: 'Search employees...',
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
                    
                    // Employee Count
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: w * 0.02),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total Employees: ${_uniqueEmployees.length}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 14,
                              fontFamily: 'Poppins',
                            ),
                          ),
                          Text(
                            'Showing: ${_filteredEmployees.length}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 14,
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const Divider(color: Color(0xFF3E7DDD)),
                    
                    // Employee List
                    Expanded(
                      child: _isLoading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFF3FA9F5),
                              ),
                            )
                          : _filteredEmployees.isEmpty
                              ? Center(
                                  child: Text(
                                    'No employees found',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.6),
                                      fontSize: 16,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: _filteredEmployees.length,
                                  itemBuilder: (context, index) {
                                    final emp = _filteredEmployees[index];
                                    final fingerprintCount = emp['fingerprint_count'] as int;
                                    return ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: const Color(0xFF3FA9F5),
                                        child: Text(
                                          (emp['employee_name'] ?? 'U')[0].toUpperCase(),
                                          style: const TextStyle(color: Colors.white),
                                        ),
                                      ),
                                      title: Text(
                                        emp['employee_name'] ?? 'Unknown',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontFamily: 'Poppins',
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'ID: ${emp['employee_id']}',
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(0.7),
                                              fontSize: 12,
                                            ),
                                          ),
                                          Text(
                                            'Fingerprints: $fingerprintCount',
                                            style: TextStyle(
                                              color: fingerprintCount >= 6 
                                                ? Colors.green 
                                                : Colors.orange,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
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
}
