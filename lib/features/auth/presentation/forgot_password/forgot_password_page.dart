import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/auth_repository.dart';


class ForgotPasswordPage extends ConsumerStatefulWidget {

  const ForgotPasswordPage({
    super.key,
  });

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();

}



class _ForgotPasswordPageState
    extends ConsumerState<ForgotPasswordPage> {


  final emailController =
      TextEditingController();


  bool loading = false;



  Future<void> resetPassword() async {

    final email =
        emailController.text.trim();



    if(email.isEmpty){

      showMessage(
        "Enter your email",
      );

      return;

    }



    setState(() {
      loading = true;
    });



    try {


      await ref
          .read(authRepositoryProvider)
          .sendPasswordResetEmail(
            email,
          );



      if(!mounted) return;



      showEmailSentDialog(email);



    } on FirebaseAuthException catch(e){


      String message;



      switch(e.code){


        case "invalid-email":

          message =
          "Invalid email address";

          break;



        case "user-not-found":

          message =
          "No account found with this email";

          break;



        case "too-many-requests":

          message =
          "Too many attempts. Try again later";

          break;



        default:

          message =
              e.message ??
              "Something went wrong";

      }



      showMessage(message);



    } finally {


      if(mounted){

        setState(() {

          loading = false;

        });

      }

    }

  }





  void showEmailSentDialog(String email){


    showDialog(

      context: context,

      barrierDismissible: false,


      builder: (context){


        return Dialog(

          backgroundColor:
          Colors.white,


          insetPadding:
          const EdgeInsets.symmetric(
            horizontal:28,
          ),


          shape:
          RoundedRectangleBorder(

            borderRadius:
            BorderRadius.circular(
              28,
            ),

          ),



          child:
          Padding(

            padding:
            const EdgeInsets.fromLTRB(
              20,
              30,
              20,
              25,
            ),



            child:
            Column(

              mainAxisSize:
              MainAxisSize.min,


              children: [



                Container(

                  height:42,

                  width:42,


                  decoration:
                  BoxDecoration(

                    color:
                    Colors.black,


                    borderRadius:
                    BorderRadius.circular(
                      12,
                    ),

                  ),


                  child:
                  const Icon(

                    Icons.mark_email_read_outlined,

                    color:
                    Colors.white,

                    size:22,

                  ),

                ),




                const SizedBox(
                  height:18,
                ),




                const Text(

                  "Check your inbox",

                  style:
                  TextStyle(

                    fontSize:22,

                    fontWeight:
                    FontWeight.w600,

                  ),

                ),




                const SizedBox(
                  height:8,
                ),




                Text(

                  "A password reset link has been sent to\n$email",

                  textAlign:
                  TextAlign.center,


                  style:
                  TextStyle(

                    fontSize:13,

                    height:1.4,

                    color:
                    Colors.grey.shade600,

                  ),

                ),





                const SizedBox(
                  height:22,
                ),




                SizedBox(

                  width:
                  double.infinity,


                  height:
                  48,



                  child:
                  ElevatedButton(

                    style:
                    ElevatedButton.styleFrom(

                      backgroundColor:
                      Colors.black,


                      foregroundColor:
                      Colors.white,


                      elevation:
                      0,


                      shape:
                      RoundedRectangleBorder(

                        borderRadius:
                        BorderRadius.circular(
                          30,
                        ),

                      ),

                    ),



                    onPressed: (){


                      Navigator.pop(context);



                      context.push(

                        "/check-email",

                        extra:
                        email,

                      );


                    },



                    child:
                    const Text(

                      "Continue",

                      style:
                      TextStyle(

                        fontSize:14,

                      ),

                    ),

                  ),

                ),





                const SizedBox(
                  height:8,
                ),




                TextButton(


                  onPressed: (){


                    Navigator.pop(context);


                    resetPassword();


                  },



                  child:
                  const Text(

                    "Resend email",

                    style:
                    TextStyle(

                      color:
                      Colors.black,

                      fontSize:14,

                    ),

                  ),

                ),



              ],

            ),

          ),

        );

      },

    );

  }





  void showMessage(String text){

    ScaffoldMessenger.of(context)
        .showSnackBar(

      SnackBar(

        content:
        Text(text),

      ),

    );

  }





  @override
  Widget build(BuildContext context){


    return Scaffold(

      backgroundColor:
      Colors.white,



      body:
      SafeArea(

        child:
        Padding(

          padding:
          const EdgeInsets.symmetric(
            horizontal:12,
          ),



          child:
          Column(

            children: [



              const SizedBox(
                height:20,
              ),



              Align(

                alignment:
                Alignment.topLeft,


                child:
                IconButton(

                  onPressed: (){

                    context.pop();

                  },


                  icon:
                  const Icon(

                    Icons.arrow_back_ios_new,

                    size:20,

                  ),

                ),

              ),




              const Spacer(),




              Container(

                height:44,

                width:44,


                decoration:
                BoxDecoration(

                  color:
                  Colors.black,


                  borderRadius:
                  BorderRadius.circular(
                    12,
                  ),

                ),


                child:
                const Icon(

                  Icons.lock_reset,

                  color:
                  Colors.white,

                  size:24,

                ),

              ),




              const SizedBox(
                height:22,
              ),




              const Text(

                "Forgot Password?",


                style:
                TextStyle(

                  fontSize:25,

                  fontWeight:
                  FontWeight.w600,

                ),

              ),




              const SizedBox(
                height:10,
              ),




              Text(

                "Enter your email and we will send you a link to reset your password.",

                textAlign:
                TextAlign.center,


                style:
                TextStyle(

                  fontSize:14,

                  color:
                  Colors.grey.shade600,

                ),

              ),




              const SizedBox(
                height:28,
              ),




              TextField(

                controller:
                emailController,


                keyboardType:
                TextInputType.emailAddress,


                decoration:
                InputDecoration(

                  hintText:
                  "Email",


                  contentPadding:
                  const EdgeInsets.symmetric(

                    horizontal:16,

                    vertical:16,

                  ),


                  border:
                  OutlineInputBorder(

                    borderRadius:
                    BorderRadius.circular(
                      12,
                    ),

                  ),

                ),

              ),




              const SizedBox(
                height:18,
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
                        30,
                      ),

                    ),

                  ),


                  onPressed:

                  loading
                      ? null
                      : resetPassword,


                  child:

                  loading

                      ?

                  const SizedBox(

                    height:20,

                    width:20,

                    child:
                    CircularProgressIndicator(

                      color:
                      Colors.white,

                    ),

                  )

                      :

                  const Text(
                    "Continue",
                  ),

                ),

              ),




              const Spacer(),




              Padding(

                padding:
                const EdgeInsets.only(
                  bottom:25,
                ),


                child:
                Text(

                  "Didn't receive the email?\n"
                  "Check your spam folder. Firebase sends this email automatically.",


                  textAlign:
                  TextAlign.center,


                  style:
                  TextStyle(

                    fontSize:12,

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




  @override
  void dispose(){

    emailController.dispose();

    super.dispose();

  }

}