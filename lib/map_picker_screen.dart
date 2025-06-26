import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapPickerScreen extends StatefulWidget {
  @override
  _MapPickerScreenState createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  LatLng? _pickedLocation;

  @override
  Widget build(BuildContext context) {
    final LatLng initialCenter =
        LatLng(31.585146, 74.349744); // Default center (Lahore)

    return Scaffold(
      appBar: AppBar(
        title: Text('Pick Branch Location'),
        actions: [
          if (_pickedLocation != null)
            IconButton(
              icon: Icon(Icons.check),
              onPressed: () {
                Navigator.pop(context,
                    '${_pickedLocation!.latitude},${_pickedLocation!.longitude}');
              },
            ),
        ],
      ),
      body: FlutterMap(
        options: MapOptions(
          center: initialCenter,
          zoom: 13.0,
          onTap: (tapPosition, point) {
            setState(() {
              _pickedLocation = point;
            });
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            subdomains: const ['a', 'b', 'c'],
            userAgentPackageName: 'com.example.app',
          ),
          if (_pickedLocation != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: _pickedLocation!,
                  width: 40,
                  height: 40,
                  child: Icon(Icons.location_on, color: Colors.red, size: 40),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
