const std = @import("std");

// chebval was ported from numpy.polynomial.chebval.
//
// Copyright (c) 2005-2023, NumPy Developers.
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//
//    * Redistributions in binary form must reproduce the above
//       copyright notice, this list of conditions and the following
//       disclaimer in the documentation and/or other materials provided
//       with the distribution.
//
//    * Neither the name of the NumPy Developers nor the names of any
//       contributors may be used to endorse or promote products derived
//       from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pub fn chebval(x: f32, c: []f32) f32 {
    switch (c.len) {
        1 => {
            return c[0];
        },
        2 => {
            return c[0] + c[1] * x;
        },
        else => {
            const x2 = 2 * x;
            var c0 = c[c.len - 2];
            var c1 = c[c.len - 1];
            for (3..(c.len + 1)) |i| {
                var tmp = c0;
                c0 = c[c.len - i] - c1;
                c1 = tmp + c1 * x2;
            }
            return c0 + c1 * x;
        },
    }
}

pub fn clipf(x: f32, lower: f32, upper: f32) f32 {
    return @max(lower, @min(x, upper));
}
