import 'package:flutter/material.dart';
import 'bluetooth.dart';

MyBluetooth myBluetooth = MyBluetooth();

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
                'SP',
              ),
              TextField(
                decoration: InputDecoration(
                    hintText: 'Enter a gear number'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(

        child: Icon(Icons.bluetooth),
      ),
    );
  }
}
