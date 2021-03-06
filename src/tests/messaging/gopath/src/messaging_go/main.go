package main

//-*-Mode:Go;coding:utf-8;tab-width:4;c-basic-offset:4-*-
// ex: set ft=go fenc=utf-8 sts=4 ts=4 sw=4 noet nomod:
//
// MIT License
//
// Copyright (c) 2017-2020 Michael Truog <mjtruog at protonmail dot com>
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the "Software"),
// to deal in the Software without restriction, including without limitation
// the rights to use, copy, modify, merge, publish, distribute, sublicense,
// and/or sell copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
// DEALINGS IN THE SOFTWARE.
//

import (
	"cloudi"
	"fmt"
	"math"
	"os"
	"reflect"
	"sort"
	"strconv"
	"strings"
	"sync"
)

func task(threadIndex uint32, execution *sync.WaitGroup) {
	defer execution.Done()
	api, err := cloudi.API(threadIndex, nil)
	if err != nil {
		cloudi.ErrorWrite(os.Stderr, err)
		return
	}
	err = api.Subscribe("a/b/c/d", sequence1ABCD)
	if err != nil {
		cloudi.ErrorWrite(os.Stderr, err)
		return
	}
	err = api.Subscribe("a/b/c/*", sequence1ABCX)
	if err != nil {
		cloudi.ErrorWrite(os.Stderr, err)
		return
	}
	err = api.Subscribe("a/b/*/d", sequence1ABXD)
	if err != nil {
		cloudi.ErrorWrite(os.Stderr, err)
		return
	}
	err = api.Subscribe("a/*/c/d", sequence1AXCD)
	if err != nil {
		cloudi.ErrorWrite(os.Stderr, err)
		return
	}
	err = api.Subscribe("*/b/c/d", sequence1XBCD)
	if err != nil {
		cloudi.ErrorWrite(os.Stderr, err)
		return
	}
	err = api.Subscribe("a/b/*", sequence1ABX)
	if err != nil {
		cloudi.ErrorWrite(os.Stderr, err)
		return
	}
	err = api.Subscribe("a/*/d", sequence1AXD)
	if err != nil {
		cloudi.ErrorWrite(os.Stderr, err)
		return
	}
	err = api.Subscribe("*/c/d", sequence1XCD)
	if err != nil {
		cloudi.ErrorWrite(os.Stderr, err)
		return
	}
	err = api.Subscribe("a/*", sequence1AX)
	if err != nil {
		cloudi.ErrorWrite(os.Stderr, err)
		return
	}
	err = api.Subscribe("*/d", sequence1XD)
	if err != nil {
		cloudi.ErrorWrite(os.Stderr, err)
		return
	}
	err = api.Subscribe("*", sequence1X)
	if err != nil {
		cloudi.ErrorWrite(os.Stderr, err)
		return
	}
	err = api.Subscribe("sequence1", sequence1)
	if err != nil {
		cloudi.ErrorWrite(os.Stderr, err)
		return
	}
	err = api.Subscribe("e", sequence2E1)
	if err != nil {
		cloudi.ErrorWrite(os.Stderr, err)
		return
	}
	err = api.Subscribe("e", sequence2E2)
	if err != nil {
		cloudi.ErrorWrite(os.Stderr, err)
		return
	}
	err = api.Subscribe("e", sequence2E3)
	if err != nil {
		cloudi.ErrorWrite(os.Stderr, err)
		return
	}
	err = api.Subscribe("e", sequence2E4)
	if err != nil {
		cloudi.ErrorWrite(os.Stderr, err)
		return
	}
	err = api.Subscribe("e", sequence2E5)
	if err != nil {
		cloudi.ErrorWrite(os.Stderr, err)
		return
	}
	err = api.Subscribe("e", sequence2E6)
	if err != nil {
		cloudi.ErrorWrite(os.Stderr, err)
		return
	}
	err = api.Subscribe("e", sequence2E7)
	if err != nil {
		cloudi.ErrorWrite(os.Stderr, err)
		return
	}
	err = api.Subscribe("e", sequence2E8)
	if err != nil {
		cloudi.ErrorWrite(os.Stderr, err)
		return
	}
	err = api.Subscribe("sequence2", sequence2)
	if err != nil {
		cloudi.ErrorWrite(os.Stderr, err)
		return
	}
	err = api.Subscribe("f1", sequence3F1)
	if err != nil {
		cloudi.ErrorWrite(os.Stderr, err)
		return
	}
	err = api.Subscribe("f2", sequence3F2)
	if err != nil {
		cloudi.ErrorWrite(os.Stderr, err)
		return
	}
	err = api.Subscribe("g1", sequence3G1)
	if err != nil {
		cloudi.ErrorWrite(os.Stderr, err)
		return
	}
	err = api.Subscribe("sequence3", sequence3)
	if err != nil {
		cloudi.ErrorWrite(os.Stderr, err)
		return
	}
	if threadIndex == 0 {
		_, err = api.SendAsync(api.Prefix()+"sequence1", []byte{}, []byte("1"))
		if err != nil {
			cloudi.ErrorWrite(os.Stderr, err)
			return
		}
	}
	_, err = api.Poll(-1)
	if err != nil {
		cloudi.ErrorWrite(os.Stderr, err)
	}
	os.Stdout.WriteString("terminate messaging go\n")
}

func assert(value interface{}, expected ...interface{}) {
	for _, expect := range expected {
		if reflect.DeepEqual(value, expect) {
			return
		}
	}
	panic("assert failed!")
}

func sequence1ABCD(requestType int, name, pattern string, requestInfo, request []byte, timeout uint32, priority int8, transId [16]byte, pid cloudi.Source, state interface{}, api *cloudi.Instance) ([]byte, []byte, error) {
	assert(pattern, api.Prefix()+"a/b/c/d")
	assert(request, []byte("test1"))
	return nil, request, nil
}

func sequence1ABCX(requestType int, name, pattern string, requestInfo, request []byte, timeout uint32, priority int8, transId [16]byte, pid cloudi.Source, state interface{}, api *cloudi.Instance) ([]byte, []byte, error) {
	assert(pattern, api.Prefix()+"a/b/c/*")
	assert(request, []byte("test2"), []byte("test3"))
	return nil, request, nil
}

func sequence1ABXD(requestType int, name, pattern string, requestInfo, request []byte, timeout uint32, priority int8, transId [16]byte, pid cloudi.Source, state interface{}, api *cloudi.Instance) ([]byte, []byte, error) {
	assert(pattern, api.Prefix()+"a/b/*/d")
	assert(request, []byte("test4"), []byte("test5"))
	return nil, request, nil
}

func sequence1AXCD(requestType int, name, pattern string, requestInfo, request []byte, timeout uint32, priority int8, transId [16]byte, pid cloudi.Source, state interface{}, api *cloudi.Instance) ([]byte, []byte, error) {
	assert(pattern, api.Prefix()+"a/*/c/d")
	assert(request, []byte("test6"), []byte("test7"))
	return nil, request, nil
}

func sequence1XBCD(requestType int, name, pattern string, requestInfo, request []byte, timeout uint32, priority int8, transId [16]byte, pid cloudi.Source, state interface{}, api *cloudi.Instance) ([]byte, []byte, error) {
	assert(pattern, api.Prefix()+"*/b/c/d")
	assert(request, []byte("test8"), []byte("test9"))
	return nil, request, nil
}

func sequence1ABX(requestType int, name, pattern string, requestInfo, request []byte, timeout uint32, priority int8, transId [16]byte, pid cloudi.Source, state interface{}, api *cloudi.Instance) ([]byte, []byte, error) {
	assert(pattern, api.Prefix()+"a/b/*")
	assert(request, []byte("test10"))
	return nil, request, nil
}

func sequence1AXD(requestType int, name, pattern string, requestInfo, request []byte, timeout uint32, priority int8, transId [16]byte, pid cloudi.Source, state interface{}, api *cloudi.Instance) ([]byte, []byte, error) {
	assert(pattern, api.Prefix()+"a/*/d")
	assert(request, []byte("test11"))
	return nil, request, nil
}

func sequence1XCD(requestType int, name, pattern string, requestInfo, request []byte, timeout uint32, priority int8, transId [16]byte, pid cloudi.Source, state interface{}, api *cloudi.Instance) ([]byte, []byte, error) {
	assert(pattern, api.Prefix()+"*/c/d")
	assert(request, []byte("test12"))
	return nil, request, nil
}

func sequence1AX(requestType int, name, pattern string, requestInfo, request []byte, timeout uint32, priority int8, transId [16]byte, pid cloudi.Source, state interface{}, api *cloudi.Instance) ([]byte, []byte, error) {
	assert(pattern, api.Prefix()+"a/*")
	assert(request, []byte("test13"))
	return nil, request, nil
}

func sequence1XD(requestType int, name, pattern string, requestInfo, request []byte, timeout uint32, priority int8, transId [16]byte, pid cloudi.Source, state interface{}, api *cloudi.Instance) ([]byte, []byte, error) {
	assert(pattern, api.Prefix()+"*/d")
	assert(request, []byte("test14"))
	return nil, request, nil
}

func sequence1X(requestType int, name, pattern string, requestInfo, request []byte, timeout uint32, priority int8, transId [16]byte, pid cloudi.Source, state interface{}, api *cloudi.Instance) ([]byte, []byte, error) {
	assert(pattern, api.Prefix()+"*")
	assert(request, []byte("test15"))
	return nil, request, nil
}

func sequence1(requestType int, name, pattern string, requestInfo, request []byte, timeout uint32, priority int8, transId [16]byte, pid cloudi.Source, state interface{}, api *cloudi.Instance) ([]byte, []byte, error) {
	var err error
	// consume all the 'end' responses from all sequences handled
	// by this service
	done := false
	for !done {
		var response []byte
		_, response, _, err = api.RecvAsync(1000)
		if err != nil {
			panic(err)
		}
		done = (string(response) != "end")
	}
	iteration, err := strconv.ParseUint(string(request), 10, 64)
	if err != nil {
		panic(err)
	}
	os.Stdout.WriteString(fmt.Sprintf("messaging sequence1 start go (%d)\n", iteration))
	var test1Id []byte
	test1Id, err = api.SendAsync(api.Prefix()+"a/b/c/d", []byte{}, []byte("test1"))
	if err != nil {
		panic(err)
	}
	var test2Id []byte
	test2Id, err = api.SendAsync(api.Prefix()+"a/b/c/z", []byte{}, []byte("test2"))
	if err != nil {
		panic(err)
	}
	var test3Id []byte
	test3Id, err = api.SendAsync(api.Prefix()+"a/b/c/dd", []byte{}, []byte("test3"))
	if err != nil {
		panic(err)
	}
	var test4Id []byte
	test4Id, err = api.SendAsync(api.Prefix()+"a/b/z/d", []byte{}, []byte("test4"))
	if err != nil {
		panic(err)
	}
	var test5Id []byte
	test5Id, err = api.SendAsync(api.Prefix()+"a/b/cc/d", []byte{}, []byte("test5"))
	if err != nil {
		panic(err)
	}
	var test6Id []byte
	test6Id, err = api.SendAsync(api.Prefix()+"a/z/c/d", []byte{}, []byte("test6"))
	if err != nil {
		panic(err)
	}
	var test7Id []byte
	test7Id, err = api.SendAsync(api.Prefix()+"a/bb/c/d", []byte{}, []byte("test7"))
	if err != nil {
		panic(err)
	}
	var test8Id []byte
	test8Id, err = api.SendAsync(api.Prefix()+"z/b/c/d", []byte{}, []byte("test8"))
	if err != nil {
		panic(err)
	}
	var test9Id []byte
	test9Id, err = api.SendAsync(api.Prefix()+"aa/b/c/d", []byte{}, []byte("test9"))
	if err != nil {
		panic(err)
	}
	var test10Id []byte
	test10Id, err = api.SendAsync(api.Prefix()+"a/b/czd", []byte{}, []byte("test10"))
	if err != nil {
		panic(err)
	}
	var test11Id []byte
	test11Id, err = api.SendAsync(api.Prefix()+"a/bzc/d", []byte{}, []byte("test11"))
	if err != nil {
		panic(err)
	}
	var test12Id []byte
	test12Id, err = api.SendAsync(api.Prefix()+"azb/c/d", []byte{}, []byte("test12"))
	if err != nil {
		panic(err)
	}
	var test13Id []byte
	test13Id, err = api.SendAsync(api.Prefix()+"a/bzczd", []byte{}, []byte("test13"))
	if err != nil {
		panic(err)
	}
	var test14Id []byte
	test14Id, err = api.SendAsync(api.Prefix()+"azbzc/d", []byte{}, []byte("test14"))
	if err != nil {
		panic(err)
	}
	var test15Id []byte
	test15Id, err = api.SendAsync(api.Prefix()+"azbzczd", []byte{}, []byte("test15"))
	if err != nil {
		panic(err)
	}
	// n.b., depends on cloudi_core_i_constants.hrl having
	// RECV_ASYNC_STRATEGY == recv_async_select_oldest
	_, _, _, err = api.RecvAsync(test1Id, false)
	if err != nil {
		panic(err)
	}
	var test1Check []byte
	var test1IdCheck []byte
	_, test1Check, test1IdCheck, err = api.RecvAsync()
	if err != nil {
		panic(err)
	}
	assert(test1Check, []byte("test1"))
	assert(test1Id, test1IdCheck)
	_, _, _, err = api.RecvAsync(test2Id, false)
	if err != nil {
		panic(err)
	}
	var test2Check []byte
	var test2IdCheck []byte
	_, test2Check, test2IdCheck, err = api.RecvAsync()
	if err != nil {
		panic(err)
	}
	assert(test2Check, []byte("test2"))
	assert(test2Id, test2IdCheck)
	_, _, _, err = api.RecvAsync(test3Id, false)
	if err != nil {
		panic(err)
	}
	var test3Check []byte
	var test3IdCheck []byte
	_, test3Check, test3IdCheck, err = api.RecvAsync()
	if err != nil {
		panic(err)
	}
	assert(test3Check, []byte("test3"))
	assert(test3Id, test3IdCheck)
	_, _, _, err = api.RecvAsync(test4Id, false)
	if err != nil {
		panic(err)
	}
	var test4Check []byte
	var test4IdCheck []byte
	_, test4Check, test4IdCheck, err = api.RecvAsync()
	if err != nil {
		panic(err)
	}
	assert(test4Check, []byte("test4"))
	assert(test4Id, test4IdCheck)
	_, _, _, err = api.RecvAsync(test5Id, false)
	if err != nil {
		panic(err)
	}
	var test5Check []byte
	var test5IdCheck []byte
	_, test5Check, test5IdCheck, err = api.RecvAsync()
	if err != nil {
		panic(err)
	}
	assert(test5Check, []byte("test5"))
	assert(test5Id, test5IdCheck)
	_, _, _, err = api.RecvAsync(test6Id, false)
	if err != nil {
		panic(err)
	}
	var test6Check []byte
	var test6IdCheck []byte
	_, test6Check, test6IdCheck, err = api.RecvAsync()
	if err != nil {
		panic(err)
	}
	assert(test6Check, []byte("test6"))
	assert(test6Id, test6IdCheck)
	_, _, _, err = api.RecvAsync(test7Id, false)
	if err != nil {
		panic(err)
	}
	var test7Check []byte
	var test7IdCheck []byte
	_, test7Check, test7IdCheck, err = api.RecvAsync()
	if err != nil {
		panic(err)
	}
	assert(test7Check, []byte("test7"))
	assert(test7Id, test7IdCheck)
	_, _, _, err = api.RecvAsync(test8Id, false)
	if err != nil {
		panic(err)
	}
	var test8Check []byte
	var test8IdCheck []byte
	_, test8Check, test8IdCheck, err = api.RecvAsync()
	if err != nil {
		panic(err)
	}
	assert(test8Check, []byte("test8"))
	assert(test8Id, test8IdCheck)
	_, _, _, err = api.RecvAsync(test9Id, false)
	if err != nil {
		panic(err)
	}
	var test9Check []byte
	var test9IdCheck []byte
	_, test9Check, test9IdCheck, err = api.RecvAsync()
	if err != nil {
		panic(err)
	}
	assert(test9Check, []byte("test9"))
	assert(test9Id, test9IdCheck)
	_, _, _, err = api.RecvAsync(test10Id, false)
	if err != nil {
		panic(err)
	}
	var test10Check []byte
	var test10IdCheck []byte
	_, test10Check, test10IdCheck, err = api.RecvAsync()
	if err != nil {
		panic(err)
	}
	assert(test10Check, []byte("test10"))
	assert(test10Id, test10IdCheck)
	_, _, _, err = api.RecvAsync(test11Id, false)
	if err != nil {
		panic(err)
	}
	var test11Check []byte
	var test11IdCheck []byte
	_, test11Check, test11IdCheck, err = api.RecvAsync()
	if err != nil {
		panic(err)
	}
	assert(test11Check, []byte("test11"))
	assert(test11Id, test11IdCheck)
	_, _, _, err = api.RecvAsync(test12Id, false)
	if err != nil {
		panic(err)
	}
	var test12Check []byte
	var test12IdCheck []byte
	_, test12Check, test12IdCheck, err = api.RecvAsync()
	if err != nil {
		panic(err)
	}
	assert(test12Check, []byte("test12"))
	assert(test12Id, test12IdCheck)
	_, _, _, err = api.RecvAsync(test13Id, false)
	if err != nil {
		panic(err)
	}
	var test13Check []byte
	var test13IdCheck []byte
	_, test13Check, test13IdCheck, err = api.RecvAsync()
	if err != nil {
		panic(err)
	}
	assert(test13Check, []byte("test13"))
	assert(test13Id, test13IdCheck)
	_, _, _, err = api.RecvAsync(test14Id, false)
	if err != nil {
		panic(err)
	}
	var test14Check []byte
	var test14IdCheck []byte
	_, test14Check, test14IdCheck, err = api.RecvAsync()
	if err != nil {
		panic(err)
	}
	assert(test14Check, []byte("test14"))
	assert(test14Id, test14IdCheck)
	_, _, _, err = api.RecvAsync(test15Id, false)
	if err != nil {
		panic(err)
	}
	var test15Check []byte
	var test15IdCheck []byte
	_, test15Check, test15IdCheck, err = api.RecvAsync()
	if err != nil {
		panic(err)
	}
	assert(test15Check, []byte("test15"))
	assert(test15Id, test15IdCheck)
	os.Stdout.WriteString(fmt.Sprintf("messaging sequence1 end go (%d)\n", iteration))
	// start sequence2
	_, err = api.SendAsync(api.Prefix()+"sequence2", []byte{}, request)
	return nil, []byte("end"), err
}

func sequence2E1(requestType int, name, pattern string, requestInfo, request []byte, timeout uint32, priority int8, transId [16]byte, pid cloudi.Source, state interface{}, api *cloudi.Instance) ([]byte, []byte, error) {
	return nil, []byte("1"), nil
}

func sequence2E2(requestType int, name, pattern string, requestInfo, request []byte, timeout uint32, priority int8, transId [16]byte, pid cloudi.Source, state interface{}, api *cloudi.Instance) ([]byte, []byte, error) {
	return nil, []byte("2"), nil
}

func sequence2E3(requestType int, name, pattern string, requestInfo, request []byte, timeout uint32, priority int8, transId [16]byte, pid cloudi.Source, state interface{}, api *cloudi.Instance) ([]byte, []byte, error) {
	return nil, []byte("3"), nil
}

func sequence2E4(requestType int, name, pattern string, requestInfo, request []byte, timeout uint32, priority int8, transId [16]byte, pid cloudi.Source, state interface{}, api *cloudi.Instance) ([]byte, []byte, error) {
	return nil, []byte("4"), nil
}

func sequence2E5(requestType int, name, pattern string, requestInfo, request []byte, timeout uint32, priority int8, transId [16]byte, pid cloudi.Source, state interface{}, api *cloudi.Instance) ([]byte, []byte, error) {
	return nil, []byte("5"), nil
}

func sequence2E6(requestType int, name, pattern string, requestInfo, request []byte, timeout uint32, priority int8, transId [16]byte, pid cloudi.Source, state interface{}, api *cloudi.Instance) ([]byte, []byte, error) {
	return nil, []byte("6"), nil
}

func sequence2E7(requestType int, name, pattern string, requestInfo, request []byte, timeout uint32, priority int8, transId [16]byte, pid cloudi.Source, state interface{}, api *cloudi.Instance) ([]byte, []byte, error) {
	return nil, []byte("7"), nil
}

func sequence2E8(requestType int, name, pattern string, requestInfo, request []byte, timeout uint32, priority int8, transId [16]byte, pid cloudi.Source, state interface{}, api *cloudi.Instance) ([]byte, []byte, error) {
	return nil, []byte("8"), nil
}

func sequence2(requestType int, name, pattern string, requestInfo, request []byte, timeout uint32, priority int8, transId [16]byte, pid cloudi.Source, state interface{}, api *cloudi.Instance) ([]byte, []byte, error) {
	iteration, err := strconv.ParseUint(string(request), 10, 64)
	if err != nil {
		panic(err)
	}
	os.Stdout.WriteString(fmt.Sprintf("messaging sequence2 start go (%d)\n", iteration))
	done := false
	for !done {
		var eIds [][]byte
		eIds, err = api.McastAsync(api.Prefix()+"e", []byte{}, []byte(" "))
		eIdsLen := len(eIds)
		var eCheck []byte
		var eIdCheck []byte
		if eIdsLen == 24 {
			eCheckList := []string{}
			for _, eId := range eIds {
				_, eCheck, eIdCheck, err = api.RecvAsync(eId)
				if err != nil {
					panic(err)
				}
				assert(eId, eIdCheck)
				eCheckList = append(eCheckList, string(eCheck))
			}
			sort.Sort(sort.StringSlice(eCheckList))
			assert(strings.Join(eCheckList, ""), "111222333444555666777888")
			done = true
		} else {
			os.Stdout.WriteString(fmt.Sprintf("Waiting for %s services to initialize\n", int(4-eIdsLen/8.0)))
			for _, eId := range eIds {
				_, _, eIdCheck, err = api.RecvAsync(eId)
				if err != nil {
					panic(err)
				}
				assert(eId, eIdCheck)
			}
			var nullId []byte
			_, _, nullId, err = api.RecvAsync(1000)
			if err != nil {
				panic(err)
			}
			assert(nullId, []byte("\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"))
		}
	}
	os.Stdout.WriteString(fmt.Sprintf("messaging sequence2 end go (%d)\n", iteration))
	_, err = api.SendAsync(api.Prefix()+"sequence3", []byte{}, request)
	return nil, []byte("end"), err
}

func sequence3F1(requestType int, name, pattern string, requestInfo, request []byte, timeout uint32, priority int8, transId [16]byte, pid cloudi.Source, state interface{}, api *cloudi.Instance) ([]byte, []byte, error) {
	requestI, err := strconv.Atoi(string(request))
	if err != nil {
		panic(err)
	}
	if requestI == 4 {
		return nil, []byte("done"), nil
	}
	requestNew := requestI + 2 // two steps forward
	api.Forward(requestType, api.Prefix()+"f2", requestInfo, []byte(fmt.Sprintf("%d", requestNew)), timeout, priority, transId, pid)
	return nil, nil, nil
}

func sequence3F2(requestType int, name, pattern string, requestInfo, request []byte, timeout uint32, priority int8, transId [16]byte, pid cloudi.Source, state interface{}, api *cloudi.Instance) ([]byte, []byte, error) {
	requestI, err := strconv.Atoi(string(request))
	if err != nil {
		panic(err)
	}
	requestNew := requestI - 1 // one step back
	api.Forward(requestType, api.Prefix()+"f1", requestInfo, []byte(fmt.Sprintf("%d", requestNew)), timeout, priority, transId, pid)
	return nil, nil, nil
}

func sequence3G1(requestType int, name, pattern string, requestInfo, request []byte, timeout uint32, priority int8, transId [16]byte, pid cloudi.Source, state interface{}, api *cloudi.Instance) ([]byte, []byte, error) {
	return nil, append(request, []byte("suffix")...), nil
}

func sequence3(requestType int, name, pattern string, requestInfo, request []byte, timeout uint32, priority int8, transId [16]byte, pid cloudi.Source, state interface{}, api *cloudi.Instance) ([]byte, []byte, error) {
	iteration, err := strconv.ParseUint(string(request), 10, 64)
	if err != nil {
		panic(err)
	}
	os.Stdout.WriteString(fmt.Sprintf("messaging sequence3 start go (%d)\n", iteration))
	test1Id, err := api.SendAsync(api.Prefix()+"f1", []byte{}, []byte("0"))
	if err != nil {
		panic(err)
	}
	var test1Check []byte
	var test1IdCheck []byte
	_, test1Check, test1IdCheck, err = api.RecvAsync(test1Id)
	if err != nil {
		panic(err)
	}
	assert(test1Id, test1IdCheck)
	assert(test1Check, []byte("done"))
	_, test2Check, _, err := api.SendSync(api.Prefix()+"g1", []byte{}, []byte("prefix_"))
	if err != nil {
		panic(err)
	}
	assert(test2Check, []byte("prefix_suffix"))
	os.Stdout.WriteString(fmt.Sprintf("messaging sequence3 end go (%d)\n", iteration))
	// start sequence2
	iteration++
	if iteration == math.MaxUint64 {
		iteration = 0
	}
	_, err = api.SendAsync(api.Prefix()+"sequence1", []byte{}, []byte(fmt.Sprintf("%d", iteration)))
	return nil, []byte("end"), err
}

func main() {
	threadCount, err := cloudi.ThreadCount()
	if err != nil {
		cloudi.ErrorExit(os.Stderr, err)
	}
	var execution sync.WaitGroup
	for threadIndex := uint32(0); threadIndex < threadCount; threadIndex++ {
		execution.Add(1)
		go task(threadIndex, &execution)
	}
	execution.Wait()
}
