import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart'; // For date formatting
import 'package:flutter_animate/flutter_animate.dart'; // For animations
import 'package:borezy/providers/user_provider.dart';
import 'package:provider/provider.dart';
import 'package:borezy/models/productmodel.dart'; // Assuming you saved the Product class in product_model.dart
import 'package:fluttertoast/fluttertoast.dart';

class BranchDashboardScreen extends StatefulWidget {
  const BranchDashboardScreen({Key? key}) : super(key: key);

  @override
  State<BranchDashboardScreen> createState() => _BranchDashboardScreenState();
}

class _BranchDashboardScreenState extends State<BranchDashboardScreen> {
  // Initialize with a single product as in your React code
  List<Product> products = [
    Product(
      pickupDate: DateTime.now(),
      returnDate: DateTime.now().add(const Duration(days: 2)),
      productCode: '',
      quantity: 0,
    ),
  ];

  List<Map<String, String>> productSuggestions = [];
  // Hardcode the branch code directly here as requested
  late String loggedInBranchCode;

  final FirebaseFirestore db = FirebaseFirestore.instance;
  final FirebaseStorage storage = FirebaseStorage.instance;

  @override
  void initState() {
    super.initState();
    // Use addPostFrameCallback to ensure context is available for Provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      if (userProvider.branchCode != null) {
        setState(() {
          loggedInBranchCode = userProvider.branchCode!;
        });
      } else {
        // Handle case where branchCode is null (e.g., show error, navigate to login)
        Fluttertoast.showToast(msg: "Branch code not available. Please log in.");
        // Example: Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => LoginScreen()));
      }
    });
  }

  void _onRefresh() {
    setState(() {
      // Reset the products list to its initial state
      products = [
        Product(
          pickupDate: DateTime.now(),
          returnDate: DateTime.now().add(const Duration(days: 2)),
          productCode: '',
          quantity: 0,
        ),
      ];
      productSuggestions = []; // Clear any existing suggestions
      // Optionally, you might clear other related states like search queries if they exist
      Fluttertoast.showToast(msg: "Page refreshed!");
    });
  }

  // Helper to format DateTime for input fields (if needed for display)
  String getFixedTime(DateTime date) {
    return DateFormat('dd-MM-yyyyTHH:mm').format(date);
  }

  // Mimics handleProductChange from React
  void handleProductChange(int index, String name, String value) async {
    setState(() {
      if (name == 'productCode') {
        products[index].productCode = value;
        // Clear fetched product details if code changes manually
        products[index].productName = '';
        products[index].price = '0.00';
        products[index].deposit = '0.00';
        products[index].imageUrl = null;
        products[index].totalQuantity = 0;
        products[index].availableQuantity = null;
        products[index].errorMessage = '';
      } else if (name == 'quantity') {
        products[index].quantity = int.tryParse(value) ?? 0;
      }
      // Add other product fields if you make them editable
    });

    if (name == 'productCode' && value.trim().isNotEmpty) {
      // Only fetch suggestions if the product code is for the current item being edited
      // and not if it's already filled by a suggestion click
      // This check might be tricky if the controller's text doesn't reflect the state immediately.
      // A simpler approach for suggestions is to always fetch if text changes.
      fetchProductSuggestions(value);
    } else {
      setState(() {
        productSuggestions = [];
      });
    }
  }

  // Mimics handleFirstProductDateChange from React
  void handleProductDateChange(DateTime? newDate, String name, int index) {
    if (newDate == null) return;
    setState(() {
      if (name == "pickupDate") {
        products[index].pickupDate = newDate;
        // Always change returnDate to 2 days from the new pickupDate
        products[index].returnDate = newDate.add(const Duration(days: 2)); // <--- MODIFIED LINE
      } else if (name == "returnDate") {
        products[index].returnDate = newDate;
        // If return date changes, ensure pickup date is not after it
        // and defaults to 2 days before new return date if it was later
        if (products[index].pickupDate.isAfter(newDate)) {
          products[index].pickupDate = newDate.subtract(const Duration(days: 2));
        }
      }
    });
  }

  // Mimics fetchProductSuggestions from React
  Future<void> fetchProductSuggestions(String searchTerm) async {
    try {
      final productsRef = db.collection('products/$loggedInBranchCode/products');
      final q = productsRef
          .where('productCode', isGreaterThanOrEqualTo: searchTerm)
          .where('productCode', isLessThanOrEqualTo: searchTerm + '\uf8ff')
          .limit(5); // Limit suggestions for better performance

      final querySnapshot = await q.get();

      final List<Map<String, String>> suggestions = [];
      for (var doc in querySnapshot.docs) {
        final productData = doc.data();
        if (productData['productCode'] != null &&
            (productData['productCode'] as String).toLowerCase().contains(searchTerm.toLowerCase())) {
          suggestions.add({
            'productCode': productData['productCode'] as String,
            'productName': productData['productName'] as String? ?? 'N/A',
          });
        }
      }

      setState(() {
        productSuggestions = suggestions;
      });

      if (suggestions.isEmpty) {
        // You might want to show a subtle message to the user if no suggestions
        // print('No products found for the logged-in branch matching search term.');
      }
    } catch (error) {
      print('Error fetching product suggestions: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching suggestions: $error')),
        );
      }
    }
  }

  // Mimics fetchProductDetails from React
  Future<void> fetchProductDetails(String productCode, int index) async {
    try {
      final productRef =
      db.doc('products/$loggedInBranchCode/products/$productCode');
      final productDoc = await productRef.get();

      if (productDoc.exists) {
        final productData = productDoc.data()!;
        final productBranchCode = productData['branchCode'] as String? ?? '';

        if (productBranchCode == loggedInBranchCode) {
          final List<dynamic>? imageUrls = productData['imageUrls'];
          final String? imagePath = imageUrls != null && imageUrls.isNotEmpty
              ? imageUrls[0] as String
              : null;

          String? imageUrl = null; // Start with null for image
          if (imagePath != null && imagePath.isNotEmpty) {
            try {
              final imageRef = storage.ref().child(imagePath);
              imageUrl = await imageRef.getDownloadURL();
            } catch (e) {
              print('Error fetching image URL: $e');
              // Keep imageUrl null, or set a local asset placeholder
            }
          }

          setState(() {
            products[index].imageUrl = imageUrl;
            products[index].price = productData['price']?.toString() ?? '0.00';
            products[index].deposit =
                productData['deposit']?.toString() ?? '0.00';
            products[index].totalQuantity =
                (productData['quantity'] as int?) ?? 0;
            products[index].priceType =
                productData['priceType'] as String? ?? 'daily';
            products[index].minimumRentalPeriod =
                (productData['minimumRentalPeriod'] as int?) ?? 1;
            products[index].extraRent = (productData['extraRent'] as int?) ?? 0;
            products[index].productName =
                productData['productName'] as String? ?? 'N/A';
            products[index].errorMessage = ''; // Clear any previous error
          });
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Product does not belong to this branch.')),
            );
          }
          setState(() {
            products[index].errorMessage = 'Product not for this branch.';
            products[index].availableQuantity = null;
            products[index].productName = '';
            products[index].price = '0.00';
            products[index].deposit = '0.00';
            products[index].totalQuantity = 0;
            products[index].imageUrl = null;
          });
        }
      } else {
        print('Product not found in Firestore.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Product with code "$productCode" not found.')),
          );
        }
        setState(() {
          products[index].errorMessage = 'Product not found.';
          products[index].availableQuantity = null;
          products[index].productName = '';
          products[index].price = '0.00';
          products[index].deposit = '0.00';
          products[index].totalQuantity = 0;
          products[index].imageUrl = null;
        });
      }
    } catch (error) {
      print('Error fetching product details: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching product details: $error')),
        );
      }
      setState(() {
        products[index].errorMessage = 'Failed to fetch product details.';
        products[index].availableQuantity = null;
      });
    }
  }

  // Mimics handleSuggestionClick from React
  void handleSuggestionClick(int index, Map<String, String> suggestion) {
    setState(() {
      products[index].productCode = suggestion['productCode']!;
      products[index].productName = suggestion['productName']!; // Set product name immediately
      productSuggestions = []; // Clear suggestions
    });
    fetchProductDetails(suggestion['productCode']!, index);
  }

  // Mimics removeProductForm (assuming you'll add this functionality)
  void removeProductForm(int index) {
    setState(() {
      products.removeAt(index);
    });
    // Optionally, show a confirmation or a Snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Product removed.')),
    );
  }

  // Mimics generateReceiptNumber (if needed, though not directly used in availability)
  Future<String> generateReceiptNumber(String branchCode) async {
    final receiptCounterRef =
    db.doc('products/$branchCode/branchCounters/receipt');

    final receiptCounterDoc = await receiptCounterRef.get();

    int receiptNumber = 1;

    if (receiptCounterDoc.exists) {
      final data = receiptCounterDoc.data();
      receiptNumber = (data!['currentValue'] as int) + 1;
    }

    await receiptCounterRef.set({'currentValue': receiptNumber});

    return '${branchCode}-REC-${receiptNumber.toString().padLeft(6, '0')}';
  }

  // Placeholder for getNextBookingId (you'll need to implement your specific logic)
  Future<String> getNextBookingId(
      DateTime pickupDate, String productCode) async {
    // This is a placeholder. In a real app, you might generate a unique ID
    // based on timestamps, a counter, or a UUID.
    // For transaction-safe unique IDs, consider a Firebase Cloud Function.
    return '${pickupDate.millisecondsSinceEpoch}-$productCode-${DateTime.now().microsecondsSinceEpoch}';
  }

  // Mimics checkAvailability from React
  Future<void> checkAvailability(int index) async {
    FocusScope.of(context).unfocus(); // Dismiss keyboard
    final product = products[index];

    // Basic validation
    if (product.productCode.isEmpty) {
      setState(() {
        products[index].errorMessage = 'Please enter a product code.';
        products[index].availableQuantity = null;
      });
      return;
    }
    if (product.quantity <= 0) {
      setState(() {
        products[index].errorMessage = 'Quantity must be greater than 0.';
        products[index].availableQuantity = null;
      });
      return;
    }
    if (product.pickupDate.isAfter(product.returnDate)) {
      setState(() {
        products[index].errorMessage = 'Pickup date cannot be after return date.';
        products[index].availableQuantity = null;
      });
      return;
    }

    final String productCode = product.productCode;
    final DateTime pickupDateObj = product.pickupDate;
    final DateTime returnDateObj = product.returnDate;
    final bookingId = await getNextBookingId(pickupDateObj, productCode);

    setState(() {
      products[index].errorMessage = ''; // Clear previous error
      products[index].availableQuantity = null; // Clear previous availability
    });

    // Show a loading indicator
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(width: 16),
            Text('Checking availability...'),
          ],
        ),
        duration: Duration(seconds: 10), // Keep it open for a while
      ),
    );

    try {
      final productRef =
      db.doc('products/$loggedInBranchCode/products/$productCode');
      final productDoc = await productRef.get();

      if (!productDoc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar(); // Hide loading
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Product not found: $productCode')),
          );
        }
        setState(() {
          products[index].errorMessage = 'Product not found.';
          products[index].availableQuantity = null; // Reset
        });
        return;
      }

      final productData = productDoc.data()!;
      final int maxAvailableQuantity = (productData['quantity'] as int?) ?? 0;

      // Update total quantity in the UI
      setState(() {
        products[index].totalQuantity = maxAvailableQuantity;
      });

      final bookingsRef = productRef.collection('bookings');

      // Efficiently query for overlapping bookings
      // A booking overlaps if:
      // (booking.pickupDate <= returnDateObj AND booking.returnDate >= pickupDateObj)

      final querySnapshot = await bookingsRef
          .where('pickupDate', isLessThanOrEqualTo: Timestamp.fromDate(returnDateObj))
          .get();

      int bookedQuantity = 0;
      for (var doc in querySnapshot.docs) {
        final bookingData = doc.data();
        final bookingPickupDate = (bookingData['pickupDate'] as Timestamp).toDate();
        final bookingReturnDate = (bookingData['returnDate'] as Timestamp).toDate();
        final bookingQuantity = bookingData['quantity'] as int? ?? 0;

        // Check for actual overlap
        if (bookingPickupDate.isBefore(returnDateObj) && bookingReturnDate.isAfter(pickupDateObj)) {
          bookedQuantity += bookingQuantity;
        }
      }

      int availableQuantity = maxAvailableQuantity - bookedQuantity;

      if (availableQuantity < 0) {
        availableQuantity = 0;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar(); // Hide loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Availability check complete. Available: $availableQuantity'),
            backgroundColor: Colors.green,
          ),
        );
      }

      setState(() {
        products[index].availableQuantity = availableQuantity;
        products[index].errorMessage = ''; // Clear error message if successful
      });
    } catch (error) {
      print('Error checking availability: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar(); // Hide loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error checking availability: $error')),
        );
      }
      setState(() {
        products[index].errorMessage =
        'Failed to check availability. Please try again.';
        products[index].availableQuantity = null; // Reset
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      appBar: AppBar(
        title: const Text('Branch Dashboard', style: TextStyle(color: Colors.black)),
        elevation: 0,
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black), // Ensure back button is black
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _onRefresh, // Call the new refresh method
            tooltip: 'Refresh Page',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title with animation
            const Text(
              '🧾 Check Product Availability',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.indigo),
            ).animate().fade(duration: 500.ms).slideY(begin: 0.2, duration: 500.ms),
            const SizedBox(height: 25),

            // Products list
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: products.length,
              itemBuilder: (context, index) {
                final product = products[index];
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  margin: const EdgeInsets.only(bottom: 24),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Delete button except first product if multiple
                      if (products.length > 1 && index > 0)
                        Align(
                          alignment: Alignment.topRight,
                          child: IconButton(
                            icon: const Icon(Icons.delete_forever, color: Colors.redAccent, size: 28),
                            onPressed: () => removeProductForm(index),
                            tooltip: 'Remove product',
                          ),
                        ),
                      if (products.length > 1 && index > 0)
                        const SizedBox(height: 8), // Spacing after delete button

                      // Pickup and Return date pickers
                      Row(
                        children: [
                          Expanded(
                            child: _buildDateTimePicker(
                              label: 'Pickup Date',
                              initialDate: product.pickupDate,
                              onDateSelected: (date) =>
                                  handleProductDateChange(date, "pickupDate", index),
                              enabled: index == 0,
                              defaultTime: const TimeOfDay(hour: 15, minute: 0), // Default 3:00 PM
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildDateTimePicker(
                              label: 'Return Date',
                              initialDate: product.returnDate,
                              onDateSelected: (date) =>
                                  handleProductDateChange(date, "returnDate", index),
                              enabled: index == 0,
                              defaultTime: const TimeOfDay(hour: 14, minute: 0), // Default 2:00 PM
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Product Code input with suggestions
                      _buildTextField(
                        label: 'Product Code',
                        value: product.productCode,
                        onChanged: (value) =>
                            handleProductChange(index, 'productCode', value),
                        suggestions: productSuggestions,
                        onSuggestionSelected: (suggestion) =>
                            handleSuggestionClick(index, suggestion),
                        hintText: 'e.g., PROD001', // Added hint text
                      ),
                      const SizedBox(height: 20),

                      // Quantity input
                      _buildTextField(
                        label: 'Quantity',
                        value: product.quantity.toString(),
                        onChanged: (value) =>
                            handleProductChange(index, 'quantity', value),
                        keyboardType: TextInputType.number,
                        hintText: 'e.g., 5', // Added hint text
                      ),
                      const SizedBox(height: 20),

                      // Product Name (read only)
                      _buildTextField(
                        label: 'Product Name',
                        value: product.productName,
                        readOnly: true,
                        placeholder: 'Auto-filled', // Improved placeholder
                      ),
                      const SizedBox(height: 20),

                      // Rent and Deposit side by side (read only)
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              label: 'Rent',
                              value: product.price,
                              readOnly: true,
                              placeholder: '₹ 0.00',
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildTextField(
                              label: 'Deposit',
                              value: product.deposit,
                              readOnly: true,
                              placeholder: '₹ 0.00',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Product image if available and not placeholder
                      if (product.imageUrl != null) // Removed placeholder check, now it's null or a valid URL
                        Center(
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: (product.imageUrl != null && product.imageUrl!.isNotEmpty)
                                  ? Image.network(
                                product.imageUrl!,
                                height: 150,
                                width: 150,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return SizedBox(
                                    height: 150,
                                    width: 150,
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        value: loadingProgress.expectedTotalBytes != null
                                            ? loadingProgress.cumulativeBytesLoaded /
                                            loadingProgress.expectedTotalBytes!
                                            : null,
                                      ),
                                    ),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) {
                                  debugPrint('--- Image Loading Error Details ---');
                                  debugPrint('Product Name: ${product.productName}');
                                  debugPrint('Failed to load image from URL: ${product.imageUrl}');
                                  debugPrint('Error: $error');
                                  debugPrint('StackTrace: $stackTrace');
                                  debugPrint('----------------------------------');

                                  return Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.broken_image, size: 80, color: Colors.grey),
                                      const SizedBox(height: 8),
                                      // Text('Error loading image', style: TextStyle(color: Colors.red, fontSize: 10)),
                                    ],
                                  );
                                },
                              )
                                  : const SizedBox(
                                height: 150,
                                width: 150,
                                child: Center(
                                  child: Icon(Icons.image_not_supported, size: 80, color: Colors.grey),
                                ),
                              ),
                            ),
                          ),
                        ),

                      const SizedBox(height: 20),

                      // Total and Availability status
                      // Assuming 'product' is an object with 'totalQuantity', 'errorMessage', and 'availableQuantity'.
// You can place this inside a ListView.builder or wherever you display individual product stock.

                      Container( // This outer container ensures it takes full width and provides some margin
                        width: double.infinity, // Make it take full available width
                        margin: const EdgeInsets.only(bottom: 12.0), // Add some space below each card
                        child: Card(
                          elevation: 4.0, // Add some shadow for a raised effect
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15.0), // Rounded corners
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20.0), // More generous padding
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Product Code/Name (Optional, but good for context)
                                // You might want to add a Text widget here for the product's name or code
                                // Text(
                                //   'Product: ${product.productCode}', // Assuming product has productCode
                                //   style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo.shade800),
                                // ),
                                // const SizedBox(height: 10),

                                Text(
                                  'Total Stock: ${product.totalQuantity}',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blueGrey.shade800,
                                  ),
                                ),
                                const SizedBox(height: 12),

                                if (product.errorMessage.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.red.shade200),
                                    ),
                                    child: Text(
                                      'Error: ${product.errorMessage}',
                                      style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600),
                                    ),
                                  )
                                else if (product.availableQuantity != null)
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Booked: ${product.totalQuantity - product.availableQuantity!}',
                                        style: TextStyle(fontSize: 17, color: Colors.blueGrey.shade700,fontWeight: FontWeight.bold,),
                                      ),
                                      const SizedBox(height: 8), // Small space between lines
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: (product.availableQuantity ?? 0) > 0 ? Colors.green.shade50 : Colors.red.shade50,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                              color: (product.availableQuantity ?? 0) > 0 ? Colors.green.shade200 : Colors.red.shade200),
                                        ),
                                        child: Text(
                                          'Available for rent: ${product.availableQuantity}',
                                          style: TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.bold,
                                            color: (product.availableQuantity ?? 0) > 0
                                                ? Colors.green.shade700
                                                : Colors.red.shade700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),


                      // Check Availability button
                      Center(
                        child: ElevatedButton.icon(
                          onPressed: () => checkAvailability(index),
                          icon: const Icon(Icons.search, size: 24),
                          label: const Text('Check Availability', style: TextStyle(fontSize: 18)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                vertical: 16, horizontal: 28),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            elevation: 5,
                            shadowColor: Colors.indigo.shade200,
                          ),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: (100 * index).ms).slideX(begin: 0.1, duration: 300.ms);
              },
            ),


            // Add new product button

          ],
        ),
      ),
    );
  }

  // Helper widget for text input fields
  Widget _buildTextField({
    required String label,
    required String value,
    ValueChanged<String>? onChanged,
    TextInputType keyboardType = TextInputType.text,
    bool readOnly = false,
    String placeholder = '',
    List<Map<String, String>> suggestions = const [],
    Function(Map<String, String>)? onSuggestionSelected,
    String hintText = '', // Added hint text parameter
  }) {
    // A key is used here to ensure the controller is properly rebuilt when the value changes
    // which can happen if the parent re-renders with a new 'value'
    final TextEditingController controller = TextEditingController(text: value);
    controller.selection = TextSelection.fromPosition(
      TextPosition(offset: controller.text.length),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.blueGrey),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          onChanged: (text) {
            // This is crucial: only call onChanged if the text actually changed
            // from the last known state to prevent redundant setState calls.
            if (onChanged != null) {
              onChanged(text);
            }
          },
          keyboardType: keyboardType,
          readOnly: readOnly,
          style: const TextStyle(fontSize: 17, color: Colors.black87),
          decoration: InputDecoration(
            hintText: hintText.isNotEmpty ? hintText : placeholder,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade400),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.indigo, width: 2),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        if (suggestions.isNotEmpty && onSuggestionSelected != null && !readOnly)
          Container(
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: suggestions.length,
              separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade300),
              itemBuilder: (context, i) {
                final suggestion = suggestions[i];
                return ListTile(
                  title: Text(
                    '${suggestion['productCode']} - ${suggestion['productName']}',
                    style: const TextStyle(fontSize: 15, color: Colors.black87),
                  ),
                  onTap: () {
                    // Update the controller and then call the handler
                    controller.text = suggestion['productCode']!;
                    onSuggestionSelected(suggestion);
                    // Dismiss keyboard after selecting a suggestion
                    FocusScope.of(context).unfocus();
                  },
                );
              },
            ),
          ),
      ],
    );
  }

  // Helper widget for date and time picker
  Widget _buildDateTimePicker({
    required String label,
    required DateTime initialDate,
    required Function(DateTime?) onDateSelected,
    bool enabled = true,
    TimeOfDay? defaultTime, // New parameter for default time
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.blueGrey),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: enabled
              ? () async {
            final DateTime? pickedDate = await showDatePicker(
              context: context,
              initialDate: initialDate,
              firstDate: DateTime.now().subtract(const Duration(days: 365 * 1)),
              lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
              builder: (context, child) {
                return Theme(
                  data: ThemeData.light().copyWith(
                    colorScheme: const ColorScheme.light(
                      primary: Colors.indigo,
                      onPrimary: Colors.white,
                      onSurface: Colors.black,
                    ),
                    textButtonTheme: TextButtonThemeData(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.indigo,
                      ),
                    ),
                  ),
                  child: child!,
                );
              },
            );

            if (pickedDate != null) {
              // If a date is picked, then show the time picker.
              // Set initialTime to the defaultTime if provided,
              // otherwise use the time from the current initialDate (which might be midnight).
              final TimeOfDay? pickedTime = await showTimePicker(
                context: context,
                initialTime: defaultTime ?? TimeOfDay.fromDateTime(initialDate), // <--- MODIFIED HERE
                builder: (context, child) {
                  return Theme(
                    data: ThemeData.light().copyWith(
                      colorScheme: const ColorScheme.light(
                        primary: Colors.indigo,
                        onPrimary: Colors.white,
                        onSurface: Colors.black,
                      ),
                      textButtonTheme: TextButtonThemeData(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.indigo,
                        ),
                      ),
                    ),
                    child: child!,
                  );
                },
              );

              if (pickedTime != null) {
                // Combine the picked date with the picked time
                final DateTime combinedDateTime = DateTime(
                  pickedDate.year,
                  pickedDate.month,
                  pickedDate.day,
                  pickedTime.hour,
                  pickedTime.minute,
                );
                onDateSelected(combinedDateTime);
              } else {
                // If time picker is cancelled but date is picked,
                // combine pickedDate with the initial time (which includes defaultTime if set).
                final DateTime combinedDateTime = DateTime(
                  pickedDate.year,
                  pickedDate.month,
                  pickedDate.day,
                  (defaultTime ?? TimeOfDay.fromDateTime(initialDate)).hour, // <--- Apply default time if time picker is cancelled
                  (defaultTime ?? TimeOfDay.fromDateTime(initialDate)).minute,
                );
                onDateSelected(combinedDateTime);
              }
            } else {
              // If date picker is cancelled, pass null or original date
              // (depending on desired behavior for cancellation)
              onDateSelected(null);
            }
          }
              : null,
          child: InputDecorator(
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade400),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.indigo, width: 2),
              ),
              filled: true,
              fillColor: enabled ? Colors.grey.shade50 : Colors.grey.shade200,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Expanded(
                  child: Text(
                    DateFormat('dd-MM-yyyy HH:mm').format(initialDate),
                    style: TextStyle(
                      fontSize: 17,
                      color: enabled ? Colors.black87 : Colors.grey.shade600,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                Icon(Icons.calendar_today, color: enabled ? Colors.indigo : Colors.grey),
              ],
            ),
          ),
        ),
      ],
    );
  }
}