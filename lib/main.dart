import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reset_equipment/gears.dart';
import 'bluetooth.dart';

MyBluetooth myBluetooth = MyBluetooth();
PipelinedScanner scanner = PipelinedScanner(myBluetooth);

Function(String msg) update = (_) {};

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Reset gears',
      theme: ThemeData(
        primarySwatch: Colors.green,
      ),
      home: MyHomePage(title: 'Reset gears'),
    );
  }
}



class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {

final textController = TextEditingController();
int gearNum;
bool pressed = true;

String slogs = 'SP';
var f1, f2, f3;


  @override
  void initState() {
    super.initState();
    //slogs =  scanner.slogs;
    update = (msg) {
      slogs = msg;
      myBluetooth.onGunConnectionChanged = (isConnected) {
        f1 = myBluetooth.gun.id();
      };
      myBluetooth.onVestConnectionChanged = (isConnected) {
        f2 = myBluetooth.vest.id();
      };
      myBluetooth.onHeadsetConnectionChanged = (isConnected) {
        f3 = myBluetooth.headset.id();
      };
      setState(() {});
    };
  }


  Widget gearNumber(){
    return  Column(
      children: <Widget>[
        Container(
          margin: EdgeInsets.all(20.0),
          child: Text(
            'Gun ' + f1.toString() ?? "null",
          ),
        ),
         Container(
           margin: EdgeInsets.all(20.0),
           child: Text(
             'Vewst ' + f2.toString() ?? "null",
           ),
         ),
          Container(
             margin: EdgeInsets.all(20.0),
             child: Text(
               'Headset ' + f3.toString() ?? "null",
          ),
         )
      ],
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Container(
          width: 200,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                slogs ?? 'null',
              ),
              TextField(
                controller: textController,
                decoration: InputDecoration(
                    hintText: 'Enter a gear number'),
                    keyboardType: TextInputType.number,
              ),
                 gearNumber(),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          //logsState();
         gearNum = int.parse(textController.text);
         GearId(GearIdLabel.SP, gearNum);
         if (pressed) {
           pressed = true;
           scanner.scanFor(GearId(GearIdLabel.SP, gearNum));
           print("======______====" + textController.text);
           print(pressed.toString());
         } else {
           pressed = false;
           print(pressed.toString());
           scanner.stopAndReset();
         }
        },
        child: Icon(Icons.bluetooth),
      ),
    );
  }
}
