package core

import (
	"context"
	"testing"
	"time"

	"github.com/pkg/errors"
	"github.com/sirupsen/logrus/hooks/test"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
)

// --- Tests ---

func TestNewScheduler(t *testing.T) {
	suite.Run(t, new(newSchedulerTestSuite))
}

func TestScheduler_Run(t *testing.T) {
	suite.Run(t, new(schedulerRunTestSuite))
}

// --- Suites ---

type newSchedulerTestSuite struct {
	suite.Suite
}

func (s *newSchedulerTestSuite) TestNewManager() {
	s.Equal(
		&Scheduler{nil, nil, nil},
		NewScheduler(nil, nil, nil),
	)
}

type schedulerRunTestSuite struct {
	suite.Suite
	manager   *MockManagerInterface
	scheduler *Scheduler
	hook      *test.Hook
}

func (s *schedulerRunTestSuite) SetupTest() {
	logger, hook := test.NewNullLogger()
	s.manager = new(MockManagerInterface)
	s.hook = hook
	s.scheduler = &Scheduler{
		ticker:  time.NewTicker(time.Microsecond * 100),
		manager: s.manager,
		logger:  logger,
	}
}

func (s *schedulerRunTestSuite) TestWithManagerError() {
	s.manager.On(`Run`, mock.Anything).Return(errors.New(`expected error`))
	ctx, cancel := context.WithCancel(context.Background())
	go func() {
		s.scheduler.Run(ctx)
	}()

	<-time.Tick(time.Microsecond * 1000)
	cancel()
	s.Equal(s.hook.LastEntry().Message, `failed to process manager run: expected error`)
}

func (s *schedulerRunTestSuite) TestWithoutManagerError() {
	s.manager.On(`Run`, mock.Anything).Return(nil)
	ctx, cancel := context.WithCancel(context.Background())
	go func() {
		s.scheduler.Run(ctx)
	}()

	<-time.Tick(time.Microsecond * 100)
	cancel()
	s.Len(s.hook.AllEntries(), 0)
}

// --- Mocks ---

// MockManagerInterface is an autogenerated mock type for the ManagerInterface type
type MockManagerInterface struct {
	mock.Mock
}

// Run provides a mock function with given fields: ctx
func (_m *MockManagerInterface) Run(ctx context.Context) error {
	ret := _m.Called(ctx)

	var r0 error
	if rf, ok := ret.Get(0).(func(context.Context) error); ok {
		r0 = rf(ctx)
	} else {
		r0 = ret.Error(0)
	}

	return r0
}
