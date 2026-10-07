#include <iostream>
#include <mutex>
#include <thread>
int main() {
  std::mutex m;
  std::thread t([&] { std::lock_guard<std::mutex> l(m); std::cout << "hello from meson" << std::endl; });
  t.join();
}
