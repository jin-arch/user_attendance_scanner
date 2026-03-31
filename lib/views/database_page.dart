import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
          SnackBar(
            content: Text('Error loading employees: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredEmployees {
    if (_searchQuery.isEmpty) return _employees;
    
    return _employees.where((employee) {
      final employeeId = (employee['employee_id'] as String? ?? '').toLowerCase();
      final employeeName = (employee['employee_name'] as String? ?? '').toLowerCase();
      return employeeId.contains(_searchQuery) || employeeName.contains(_searchQuery);
    }).toList();
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
          'Database',
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
            onPressed: _loadEmployees,
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
                // Search Bar
                Container(
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
                      hintText: 'Search by Employee ID or Name...',
                      hintStyle: TextStyle(
                        color: Colors.white70,
                        fontFamily: 'Poppins',
                      ),
                      border: InputBorder.none,
                      prefixIcon: Icon(Icons.search, color: Colors.white70),
                    ),
                  ),
                ),
                SizedBox(height: h * 0.02),
                
                // Employee Count
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
                        Icons.people_outline,
                        color: Color(0xFF3FA9F5),
                        size: 20,
                      ),
                      SizedBox(width: w * 0.01),
                      Text(
                        'Total Employees: ${_filteredEmployees.length}',
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
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.person_search_outlined,
                                    color: Colors.white70,
                                    size: 64,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _searchQuery.isEmpty
                                        ? 'No employees found'
                                        : 'No employees match your search',
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
                              itemCount: _filteredEmployees.length,
                              itemBuilder: (context, index) {
                                final employee = _filteredEmployees[index];
                                return _buildEmployeeCard(employee, w, h);
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

  Widget _buildEmployeeCard(Map<String, dynamic> employee, double w, double h) {
    final employeeId = employee['employee_id'] as String? ?? 'N/A';
    final employeeName = employee['employee_name'] as String? ?? 'Unknown';
    final fid = employee['fid'] as int? ?? 0;

    return Container(
      margin: EdgeInsets.only(bottom: h * 0.01),
      padding: EdgeInsets.all(w * 0.02),
      decoration: BoxDecoration(
        color: const Color(0xFF0B2742).withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF3E7DDD).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Profile Icon
          Container(
            width: w * 0.12,
            height: w * 0.12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF3FA9F5), Color(0xFF1B75BB)],
              ),
              border: Border.all(
                color: Colors.white.withOpacity(0.85),
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.person,
              color: Colors.white,
              size: 30,
            ),
          ),
          SizedBox(width: w * 0.02),
          
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
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.1,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: h * 0.005),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: w * 0.02,
                    vertical: h * 0.005,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1D7CFF),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'ID: $employeeId',
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'CEORUSE',
                      fontSize: 12,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                SizedBox(height: h * 0.005),
                Text(
                  'Fingerprint ID: $fid',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontFamily: 'Poppins',
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          
          // Status Indicator
          Container(
            padding: EdgeInsets.all(w * 0.015),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF4CAF50),
            ),
            child: const Icon(
              Icons.fingerprint,
              color: Colors.white,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}
