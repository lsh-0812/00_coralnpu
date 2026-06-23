#include <string.h>
#include <stdio.h>
#include <iostream>

#include <cstdio>

float input1[8] __attribute__((section(".data")));
float input2[8] __attribute__((section(".data")));
float output[8] __attribute__((section(".data")));

int main() {
//   float input1[8], input2[8], output[8];

  
  for (int i = 0; i < 8; i++) { input1[i] = (float)(i + 1); input2[i] = 0.213f; }
  
  for (int i = 0; i < 8; i++) {
    output[i] = input1[i] + input2[i];
    printf("output[%d] = %f\n", i, output[i]);
  }
  printf("Calculate Complete!\n");
  return 0;
}