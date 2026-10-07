#include <string>
#include <thread>
#include <cstdio>
extern "C" __attribute__((visibility("default"))) void greet(const char *who) {
  std::string msg = std::string("hello from cmake, ") + who;
  std::thread t([&] { std::puts(msg.c_str()); });
  t.join();
}
