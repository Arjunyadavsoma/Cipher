import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class CheckEmailPage extends StatelessWidget {

  final String email;

  const CheckEmailPage({
    super.key,
    required this.email,
  });


  @override
  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor:
      Colors.white,


      body:
      SafeArea(

        child:
        Padding(

          padding:
          const EdgeInsets.symmetric(
            horizontal: 20,
          ),


          child:
          Column(

            children: [


              const SizedBox(
                height: 40,
              ),



              const Icon(
                Icons.mark_email_read_outlined,
                size: 42,
                color: Colors.black,
              ),



              const SizedBox(
                height: 25,
              ),



              const Text(
                "Check your inbox",
                style:
                TextStyle(
                  fontSize: 24,
                  fontWeight:
                  FontWeight.w600,
                ),
              ),



              const SizedBox(
                height: 10,
              ),



              Text(
                "We sent a password reset link to\n$email",
                textAlign:
                TextAlign.center,
                style:
                TextStyle(
                  fontSize: 14,
                  color:
                  Colors.grey.shade600,
                ),
              ),



              const SizedBox(
                height: 30,
              ),



              Container(

                height: 55,

                decoration:
                BoxDecoration(

                  border:
                  Border.all(
                    color:
                    Colors.grey.shade300,
                  ),

                  borderRadius:
                  BorderRadius.circular(
                    12,
                  ),
                ),


                alignment:
                Alignment.centerLeft,


                padding:
                const EdgeInsets.symmetric(
                  horizontal: 16,
                ),


                child:
                Text(

                  "Reset link sent",

                  style:
                  TextStyle(
                    color:
                    Colors.grey.shade400,
                    fontSize: 15,
                  ),
                ),
              ),



              const SizedBox(
                height: 18,
              ),



              SizedBox(

                width:
                double.infinity,


                height:
                52,


                child:
                ElevatedButton(

                  style:
                  ElevatedButton.styleFrom(

                    backgroundColor:
                    Colors.black,


                    foregroundColor:
                    Colors.white,


                    shape:
                    RoundedRectangleBorder(

                      borderRadius:
                      BorderRadius.circular(
                        28,
                      ),

                    ),
                  ),


                  onPressed: (){

                    context.go(
                      "/login",
                    );

                  },


                  child:
                  const Text(
                    "Continue",
                  ),
                ),
              ),



              const SizedBox(
                height: 25,
              ),



              TextButton(

                onPressed: (){

                  context.pop();

                },


                child:
                const Text(
                  "Resend email",
                  style:
                  TextStyle(
                    color:
                    Colors.black,
                    fontWeight:
                    FontWeight.w500,
                  ),
                ),
              ),



              const SizedBox(
                height: 25,
              ),



              Padding(

                padding:
                const EdgeInsets.symmetric(
                  horizontal: 20,
                ),


                child:
                Text(

                  "Didn't receive the email?\nCheck your spam folder. Firebase sends this email automatically.",

                  textAlign:
                  TextAlign.center,


                  style:
                  TextStyle(

                    fontSize:
                    13,


                    color:
                    Colors.grey.shade600,

                  ),
                ),
              ),


            ],
          ),
        ),
      ),
    );
  }
}